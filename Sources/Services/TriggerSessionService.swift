import AppKit
import KeyboardShortcuts

@MainActor
final class TriggerSessionService {
    let store: ConfigurationRepository
    private let input: TextInsertionService
    private let floating: any FloatingMenuPresenting
    private let authorization: AuthorizationService
    private let monitor: TriggerEventMonitor
    private let entry: AppEntryService
    private var target: NSRunningApplication?
    private var sessionActive = true
    private var hold = HoldMenuSession()
    private var holdTask: Task<Void, Never>?
    private var previousModifiers: NSEvent.ModifierFlags = []
    private var timer: Timer?
    private var readyWasSeen = false
    private var subscription: UUID?
    var notice = ""

    init(
        store: ConfigurationRepository, input: TextInsertionService, floating: any FloatingMenuPresenting,
        authorization: AuthorizationService, monitor: TriggerEventMonitor, entry: AppEntryService
    ) {
        self.store = store
        self.input = input
        self.floating = floating
        self.authorization = authorization
        self.monitor = monitor
        self.entry = entry
    }
    func start() {
        subscription = store.observe { [weak self] in self?.invalidate() }
        floating.onDismiss = { [weak self] in self?.invalidate() }
        monitor.onFrontChanged = { [weak self] in self?.frontChanged() }
        monitor.onSessionChanged = { [weak self] active in
            self?.sessionActive = active
            if active { self?.frontChanged() } else { self?.invalidate() }
        }
        monitor.onInvalidated = { [weak self] in self?.invalidate() }
        monitor.onPermissionsChanged = { [weak self] in self?.authorization.refreshPermissions() }
        monitor.onEvent = { [weak self] in self?.observeHoldEvent($0) }
        monitor.onShortcutDown = { [weak self] in self?.beginHold(.shortcut) }
        monitor.onShortcutUp = { [weak self] in self?.releaseHold(.shortcut) }
        previousModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        monitor.start()
        authorization.refreshPermissions()
        frontChanged()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.store.isReady, !self.readyWasSeen {
                    self.readyWasSeen = true
                    self.frontChanged()
                }
                self.entry.refresh()
                if !self.store.configuration.preferences.isEnabled && !self.authorization.isPending {
                    self.invalidate()
                }
            }
        }
    }
    func stop() {
        timer?.invalidate()
        timer = nil
        invalidate()
        monitor.stop()
        if let subscription { store.removeObserver(subscription) }
        subscription = nil
    }

    func profile(for application: NSRunningApplication) -> AppProfile? {
        let identity = ApplicationIdentity(
            bundleIdentifier: application.bundleIdentifier,
            fallbackBundlePath: application.bundleURL?.path)
        return store.configuration.profiles.first { $0.application.key == identity.key }
    }

    private func isOwnShortcut(_ event: NSEvent) -> Bool {
        guard let recorded = KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar),
            let pressed = KeyboardShortcuts.Shortcut(event: event)
        else { return false }
        return recorded == pressed
    }

    private func observeHoldEvent(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == clipboardPasteEventTag { return }
        let relevant = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let previous = previousModifiers
        if event.type == .flagsChanged { previousModifiers = relevant }
        if authorization.isPending,
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
        {
            if event.type == .leftMouseUp {
                authorization.refreshPermissions()
                authorization.watchAuthorization()
            }
            return
        }
        switch event.type {
        case .flagsChanged:
            if hold.trigger == .shortcut {
                let allowed = KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar)?.modifiers ?? []
                if !relevant.isSubset(of: allowed) { invalidate() }
                return
            }
            let modifier = NSEvent.ModifierFlags(rawValue: store.configuration.preferences.clickModifier.mask)
            if hold.trigger == .modifier && hold.phase != .waitingForModifiers && hold.phase != .inserting {
                if relevant.isEmpty { releaseHold(.modifier) } else if relevant != modifier { invalidate() }
            } else if relevant == modifier && previous != modifier {
                beginHold(.modifier)
            }
        case .keyDown:
            if isOwnShortcut(event) { beginHold(.shortcut) } else if hold.id != nil { invalidate() }
        case .keyUp:
            if hold.trigger == .shortcut,
                Int(event.keyCode) == KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar)?.carbonKeyCode
            {
                releaseHold(.shortcut)
            }
        case .leftMouseDown:
            guard hold.id != nil else { return }
            let local = CGPoint(
                x: NSEvent.mouseLocation.x - floating.frame.minX,
                y: NSEvent.mouseLocation.y - floating.frame.minY)
            if !floating.isPresented || !floating.isInteractive(local) { invalidate() }
        case .rightMouseDown, .otherMouseDown, .scrollWheel:
            if hold.id != nil { invalidate() }
        default: break
        }
    }

    private func beginHold(_ source: HoldMenuSession.Trigger) {
        // Duplicate down notifications are harmless; a new trigger after release
        // invalidates the old pending paste before starting another hold.
        if hold.trigger == source, hold.phase == .checking || hold.phase == .choosing { return }
        if hold.id != nil { invalidate() }
        frontChanged()
        authorization.refreshPermissions()
        guard !authorization.isRestarting, sessionActive, store.isReady, store.configuration.preferences.isEnabled,
            authorization.authorizationStep == .ready, !input.isBusy, let target,
            target.bundleIdentifier != Bundle.main.bundleIdentifier,
            let profile = profile(for: target), profile.canTrigger(source),
            let token = hold.begin(source)
        else { return }
        let mouse = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let mode = store.configuration.preferences.menuAnchorMode
        let screens = NSScreen.screens.map(\.visibleFrame)
        holdTask = Task {
            let captured = await input.captureTarget(
                id: token, pid: target.processIdentifier,
                mouse: mouse, primaryScreenTop: top, mode: mode)
            guard !Task.isCancelled, hold.isCurrent(token), let captured, captured.id == token, triggerIsHeld(source),
                NSWorkspace.shared.frontmostApplication?.isEqual(target) == true
            else {
                await input.releaseTarget(token)
                if hold.isCurrent(token) {
                    notice = mode == .mouse ? "请先点入普通输入框，并将鼠标放在该输入框内。" : "请先点入普通输入框。"
                    invalidate()
                }
                return
            }
            let anchor = MenuAnchor(
                mode: mode, mouse: mouse, caretBounds: captured.caretBounds,
                primaryScreenTop: top, screens: screens)
            if anchor.usedMouseFallback { notice = "当前软件未提供有效光标位置，已改用鼠标位置展开。" }
            guard hold.show(token),
                floating.show(
                    profile: profile, at: anchor.point,
                    initialMouse: mouse, requiresMovement: mode == .caret)
            else {
                notice = floating.failureMessage
                invalidate()
                return
            }
        }
    }

    private func triggerIsHeld(_ source: HoldMenuSession.Trigger) -> Bool {
        let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        if source == .modifier {
            return flags.rawValue == store.configuration.preferences.clickModifier.mask
        }
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar) else { return false }
        return flags == shortcut.modifiers.intersection([.command, .option, .control, .shift])
            && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.carbonKeyCode))
    }

    private func releaseHold(_ source: HoldMenuSession.Trigger) {
        guard hold.trigger == source, hold.phase == .checking || hold.phase == .choosing else { return }
        let selected = floating.updateSelection(at: NSEvent.mouseLocation)
        let captured = hold.id
        guard let token = hold.release(source, selection: selected), let selected,
            let target, let profile = profile(for: target), profile.canTrigger(source),
            let snippet = profile.buttons.first(where: { $0.id == selected && $0.isEnabled })
        else {
            invalidate()
            if let captured { Task { await input.releaseTarget(captured) } }
            return
        }
        floating.hide()
        holdTask?.cancel()
        holdTask = Task {
            let released = await waitForModifierRelease(
                released: { NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty },
                current: { self.hold.isCurrent(token) })
            guard released else {
                if hold.isCurrent(token) {
                    notice = "修饰键尚未松开，已取消粘贴。"
                    invalidate()
                }
                return
            }
            guard !Task.isCancelled, hold.commit(token) else { return }
            _ = await input.insert(snippet, target: target, sessionID: token)
            if hold.isCurrent(token) {
                notice = input.message
                hold.cancel()
                holdTask = nil
            }
        }
    }

    private func frontChanged() {
        let next = NSWorkspace.shared.frontmostApplication
        let checking = authorization.isPending || authorization.guideVisible
        authorization.refreshPermissions()
        if checking,
            next?.bundleIdentifier == "com.apple.systempreferences"
                || next?.bundleIdentifier == Bundle.main.bundleIdentifier
        {
            if authorization.isPending { authorization.watchAuthorization() }
            target = next
            return
        }
        if let target, next?.isEqual(target) == true, !target.isTerminated { return }
        invalidate()
        target = next
    }

    func invalidate() {
        authorization.cancelGuidance()
        let captured = hold.id
        hold.cancel()
        holdTask?.cancel()
        holdTask = nil
        input.cancel()
        floating.hide()
        if let captured { Task { await input.releaseTarget(captured) } }
    }
}
