import AppKit
import KeyboardShortcuts

@MainActor
final class TriggerSessionService {
    let store: ConfigurationRepository
    private let input: ContentInsertionService
    private let floating: any FloatingMenuPresenting
    private let authorization: AuthorizationService
    private let monitor: any TriggerEventSource
    private let entry: AppEntryService
    let diagnostics: InteractionDiagnostics
    private let environment: TriggerEnvironment
    private var target: NSRunningApplication?
    private var sessionActive = true
    private var hold = HoldMenuSession()
    private var holdTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var previousModifiers: NSEvent.ModifierFlags = []
    private var timer: Timer?
    private var subscription: UUID?
    private var snapshot: CapturedInputTarget?
    private var shortcutPressed = false
    var notice = "" {
        didSet { floating.showStatus(notice, at: environment.mouse()) }
    }

    init(
        store: ConfigurationRepository, input: ContentInsertionService, floating: any FloatingMenuPresenting,
        authorization: AuthorizationService, monitor: any TriggerEventSource, entry: AppEntryService,
        diagnostics: InteractionDiagnostics = InteractionDiagnostics(), environment: TriggerEnvironment = TriggerEnvironment()
    ) {
        self.store = store
        self.input = input
        self.floating = floating
        self.authorization = authorization
        self.monitor = monitor
        self.entry = entry
        self.diagnostics = diagnostics
        self.environment = environment
    }
    func start() {
        subscription = store.observe { [weak self] in self?.invalidate(); self?.frontChanged() }
        floating.onDismiss = { [weak self] in self?.invalidate() }
        floating.onSelect = { [weak self] in self?.select($0) }
        monitor.onFrontChanged = { [weak self] in self?.frontChanged() }
        monitor.onSessionChanged = { [weak self] active in
            self?.sessionActive = active
            self?.invalidate()
            self?.frontChanged()
        }
        monitor.onInvalidated = { [weak self] in self?.invalidate() }
        monitor.onPermissionsChanged = { [weak self] in self?.authorization.refreshPermissions(); self?.refreshShortcutAvailability() }
        monitor.onEvent = { [weak self] in self?.observeHoldEvent($0) }
        monitor.onShortcutDown = { [weak self] in
            guard let self, !shortcutPressed else { return }
            shortcutPressed = true
            if hold.trigger == .shortcut { invalidate() } else { beginHold(.shortcut) }
        }
        monitor.onShortcutUp = { [weak self] in self?.shortcutPressed = false }
        previousModifiers = environment.modifiers()
        monitor.start()
        frontChanged()
        Task { [weak self] in
            await self?.input.observeTarget { [weak self] token in
                Task { @MainActor in
                    guard let self, self.hold.isCurrent(token), self.hold.phase != .inserting else { return }
                    self.invalidate()
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.frontChanged(); self?.entry.refresh() }
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
        let identity = ApplicationIdentity(bundleIdentifier: application.bundleIdentifier, fallbackBundlePath: application.bundleURL?.path)
        return store.configuration.profiles.first { $0.application.key == identity.key }
    }
    private func isOwnShortcut(_ event: NSEvent) -> Bool {
        guard let recorded = KeyboardShortcuts.getShortcut(for: .togglePhrasePerch),
            let pressed = KeyboardShortcuts.Shortcut(event: event) else { return false }
        return recorded == pressed
    }
    private func observeHoldEvent(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == clipboardPasteEventTag { return }
        let relevant = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let previous = previousModifiers
        previousModifiers = relevant
        switch event.type {
        case .flagsChanged:
            switch hold.modifierAction(current: relevant.rawValue, previous: previous.rawValue,
                configured: store.configuration.preferences.clickModifier.mask, shortcutModifiers: nil) {
            case .begin: beginHold(.modifier)
            case .release: releaseHold()
            case .cancel: invalidate()
            case .none: break
            }
        case .keyDown:
            if !isOwnShortcut(event), hold.id != nil { invalidate() }
        case .leftMouseDown:
            guard hold.id != nil else { return }
            let mouse = environment.mouse()
            let local = CGPoint(x: mouse.x - floating.frame.minX, y: mouse.y - floating.frame.minY)
            if !floating.isPresented || !floating.isInteractive(local) { invalidate() }
        case .scrollWheel:
            if hold.id != nil, !floating.frame.contains(environment.mouse()) { invalidate() }
        case .rightMouseDown, .otherMouseDown:
            if hold.id != nil { invalidate() }
        default: break
        }
    }
    private func beginHold(_ source: HoldMenuSession.Trigger) {
        if hold.trigger == source, hold.phase == .checking || hold.phase == .choosing { return }
        if hold.id != nil { invalidate() }
        frontChanged()
        guard sessionActive, store.isReady, store.configuration.preferences.isEnabled, !input.isBusy,
            let target, target.bundleIdentifier != Bundle.main.bundleIdentifier,
            let profile = profile(for: target), profile.canTrigger(source) else { return }
        let token = UUID()
        guard authorization.authorizationStep == .ready, !authorization.isRestarting else {
            diagnostics.record(token, stage: "未开始", detail: authorization.authorizationDetail)
            notice = authorization.authorizationDetail
            return
        }
        guard let token = hold.begin(source) else { return }
        diagnostics.record(token, stage: "准备输入位置")
        snapshot = nil
        notice = ""
        let mouse = environment.mouse()
        let top = environment.primaryTop()
        let mode = store.configuration.preferences.menuAnchorMode
        let screens = environment.screens()
        holdTask = Task { [weak self] in
            guard let self else { return }
            do {
                if source == .modifier { try await environment.sleep(.milliseconds(120)) }
                try Task.checkCancellation()
                guard hold.isCurrent(token) else { return }
                deadlineTask = Task { [weak self] in
                    do { try await self?.environment.sleep(.milliseconds(500)) } catch { return }
                    guard let self, hold.isCurrent(token), hold.phase == .checking else { return }
                    invalidate(reason: "输入位置读取超时，请重试。")
                }
                let captured = try await input.capture(id: token, pid: target.processIdentifier,
                    mouse: mouse, primaryScreenTop: top, mode: mode)
                guard !Task.isCancelled, hold.isCurrent(token) else { await input.releaseTarget(token); return }
                deadlineTask?.cancel()
                deadlineTask = nil
                guard var captured, captured.id == token, environment.frontmost()?.isEqual(target) == true,
                    source == .shortcut || environment.modifiers().rawValue == store.configuration.preferences.clickModifier.mask else {
                    invalidate(reason: "输入目标或触发手势已变化，请重试。")
                    return
                }
                let anchor = MenuAnchor(mode: mode, mouse: mouse, caretBounds: captured.caretBounds,
                    primaryScreenTop: top, screens: screens, editorBounds: captured.editorBounds)
                floating.interactionMode = source == .shortcut ? .persistent : .hold
                floating.menuAppearance = store.configuration.preferences.menuAppearance
                floating.titleCharacterLimit = store.configuration.preferences.menuTitleCharacterLimit
                guard hold.show(token), floating.show(profile: profile, at: anchor.point,
                    initialMouse: mouse, requiresMovement: true) else {
                    invalidate(reason: floating.failureMessage)
                    return
                }
                let origin = captured.usedCachedCaret ? "缓存光标" : anchor.source
                captured.screenID = environment.screenIdentifier(anchor.point)
                captured.anchorSource = origin
                snapshot = captured
                let copyOnInsert = store.configuration.preferences.copyOnInsert
                let canInsert = copyOnInsert ? captured.canPaste : captured.canDirectWrite
                let directUnsupported = !copyOnInsert && captured.focusKind == .editable && !captured.canDirectWrite
                let detail = directUnsupported ? "当前输入框不支持直接写入，可在设置中开启粘贴插入"
                    : (canInsert || captured.focusKind == .nonInput ? anchor.detail : "复制模式：输入位置未能确认，选中内容后复制。")
                let stage = directUnsupported ? "直接写入不可用" : (canInsert ? (copyOnInsert ? "等待粘贴选择" : "等待直接写入选择") : "仅复制")
                diagnostics.record(token, stage: stage, detail: detail,
                    anchor: origin, screenID: captured.screenID)
            } catch is CancellationError {
                await input.releaseTarget(token)
            } catch {
                if hold.isCurrent(token) { invalidate(reason: error.localizedDescription) }
                await input.releaseTarget(token)
            }
        }
    }
    private func releaseHold() {
        guard hold.trigger == .modifier else { return }
        let selection = floating.updateSelection(at: environment.mouse())
        if let selection, hold.phase == .choosing { select(selection) } else { invalidate() }
    }
    private func select(_ selection: UUID) {
        guard let source = hold.trigger, hold.phase == .choosing,
            let target, let profile = profile(for: target), profile.canTrigger(source),
            let snippet = profile.buttons.first(where: { $0.id == selection && $0.isEnabled }),
            let token = hold.select(source, selection: selection) else { return }
        floating.hide()
        diagnostics.record(token, stage: "等待释放按键")
        holdTask?.cancel()
        let copyOnInsert = snippet.attachment != nil || store.configuration.preferences.copyOnInsert
        let canPaste = copyOnInsert ? snapshot?.canPaste == true : snapshot?.canDirectWrite == true
        if !copyOnInsert, snapshot?.focusKind == .editable, snapshot?.canDirectWrite != true {
            invalidate(reason: "当前输入框不支持直接写入，可在设置中开启粘贴插入")
            return
        }
        holdTask = Task { [weak self] in
            guard let self else { return }
            let released = await waitForModifierRelease(now: environment.now, sleep: environment.sleep, released: {
                self.environment.modifiers().isEmpty && self.environment.shortcutKey().map { !self.environment.keyHeld($0) } != false
            }, current: { self.hold.isCurrent(token) })
            guard released, hold.isCurrent(token), !Task.isCancelled else {
                if hold.isCurrent(token) { invalidate(reason: "触发键尚未全部松开，已取消操作。") }
                return
            }
            guard hold.commit(token), environment.frontmost()?.isEqual(target) == true else {
                invalidate(reason: "目标应用已切换。")
                return
            }
            if !canPaste {
                guard await input.focusUnchanged(token), hold.isCurrent(token), environment.frontmost()?.isEqual(target) == true else {
                    invalidate(reason: "焦点已变化，请重新触发。")
                    return
                }
            }
            diagnostics.record(token, stage: canPaste ? (copyOnInsert ? "粘贴插入" : "直接写入") : "正在复制")
            let result = canPaste ? await input.insert(snippet, target: target, sessionID: token, copyOnInsert: copyOnInsert) : await input.copyOnly(snippet)
            Task { await input.releaseTarget(token) }
            diagnostics.record(token, stage: result.message, detail: input.message)
            guard hold.isCurrent(token) else { return }
            notice = result == .insertedVerified || result == .copied ? "" : input.message
            hold.cancel()
            snapshot = nil
            holdTask = nil
        }
    }
    private func frontChanged() {
        defer { refreshShortcutAvailability() }
        authorization.refreshPermissions()
        let next = environment.frontmost()
        if let target, next?.isEqual(target) == true, !target.isTerminated { return }
        invalidate()
        shortcutPressed = false
        previousModifiers = environment.modifiers()
        target = next
    }
    private func refreshShortcutAvailability() {
        monitor.setShortcutEnabled(sessionActive && store.isReady && store.configuration.preferences.isEnabled
            && target?.bundleIdentifier != Bundle.main.bundleIdentifier
            && target.map { profile(for: $0)?.canTrigger(.shortcut) == true } == true)
    }
    func invalidate(reason: String = "已取消") {
        let token = hold.id
        if let token { diagnostics.record(token, stage: "已取消", detail: reason) }
        hold.cancel()
        holdTask?.cancel()
        holdTask = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        snapshot = nil
        input.cancel()
        floating.hide()
        if let token { Task { await input.releaseTarget(token) } }
        if token != nil, reason != "已取消" { notice = reason }
    }
}
