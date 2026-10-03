import AppKit
import SwiftUI
@preconcurrency import ApplicationServices
import ServiceManagement
import KeyboardShortcuts
import Observation

func isCommandQuitShortcut(charactersIgnoringModifiers: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard charactersIgnoringModifiers?.lowercased() == "q" else { return false }
    return modifiers.intersection([.command, .option, .control, .shift]) == .command
}

extension KeyboardShortcuts.Name {
    static let toggleFloatingInputBar = Self("toggleFloatingInputBar")
}

@MainActor
struct AuthorizationEnvironment {
    var snapshot: () -> (accessibility: Bool, paste: Bool) = { (AXIsProcessTrusted(), CGPreflightPostEventAccess()) }
    var save: (ConfigurationStore) async -> Bool = { await $0.flush() }
    var openSettings: () -> Bool = {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    var relaunch: (URL, pid_t) throws -> Void = { url, pid in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", """
        restart_checks=0
        while kill -0 "$1" 2>/dev/null; do
            restart_checks=$((restart_checks + 1))
            [ "$restart_checks" -lt 100 ] || exit 1
            sleep 0.1
        done
        exec /usr/bin/open "$2"
        """, "PhrasePerchRestart", String(pid), url.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
    var terminate: () -> Void = { NSApp.terminate(nil) }

}

@MainActor @Observable
final class AppCoordinator: NSObject {
    let store = ConfigurationStore()
    let input = TextInsertionService()
    private(set) var accessibilityGranted = false
    private(set) var postEventsGranted = false
    private(set) var permissionFeedback = ""
    private(set) var isRestarting = false
    private(set) var restartExitReady = false
    private(set) var authorizationFlow: AuthorizationFlow
    var authorizationStep: AuthorizationFlow.Step { authorizationFlow.step }
    var authorizationDetail: String {
        switch authorizationStep {
        case .authorize: "允许读取输入位置并粘贴文案；请在系统设置中添加当前 PhrasePerch 并开启。"
        case .restart: "系统授权已开启，请重启 PhrasePerch 使权限生效。"
        case .ready: "读取输入位置与粘贴文案均已就绪。"
        case .reauthorize: "重启后粘贴仍未就绪；请在系统设置中重新添加当前 PhrasePerch。"
        }
    }
    var authorizationStatus: InputAuthorizationStatus {
        InputAuthorizationStatus(accessibility: accessibilityGranted, paste: postEventsGranted)
    }
    var dockIconVisible: Bool { entryVisibility.dock }
    var menuBarIconVisible: Bool { entryVisibility.menuBar }
    private(set) var entryVisibility = AppEntryVisibility.load()
    private(set) var mouseMonitorAvailable = false
    private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    var notice = ""
    private let floating = FloatingPanelController()
    private let authorizationGuide = AuthorizationGuideController()
    private var authorizationTask: Task<Void, Never>?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var target: NSRunningApplication?
    private var sessionActive = true
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var mouseMonitor: Any?
    private var localMonitor: Any?
    private var hold = HoldMenuSession()
    private var holdTask: Task<Void, Never>?
    private var previousModifiers: NSEvent.ModifierFlags = []
    private var timer: Timer?
    private var readyWasSeen = false
    private var authorizationPending = false
    private var permissionTimer: Timer?
    private var permissionDeadline = Date.distantPast
    private let authorizationEnvironment: AuthorizationEnvironment
    private let authorizationDefaults: UserDefaults
    static let restartPendingKey = "PhrasePerch.authorizationRestartPending"

    override convenience init() { self.init(authorization: AuthorizationEnvironment()) }
    init(authorization: AuthorizationEnvironment, defaults: UserDefaults = .standard) {
        authorizationEnvironment = authorization
        authorizationDefaults = defaults
        authorizationFlow = AuthorizationFlow(afterRestart: defaults.string(forKey: Self.restartPendingKey) == Bundle.main.bundlePath)
        defaults.removeObject(forKey: Self.restartPendingKey)
        super.init()
        store.onChange = { [weak self] in self?.invalidate() }
        floating.onDismiss = { [weak self] in
            self?.invalidate()
        }
        authorizationGuide.onDragEnded = { [weak self] accepted in
            guard let self else { return }
            notice = accepted ? "应用已拖入，请在系统列表中开启开关，再返回重启。" : "尚未添加，请重新拖入应用。"
            refreshPermissions(); watchAuthorization()
        }

    }
    func start() {
        applyEntryVisibility()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.frontChanged() }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] in self?.frontChanged() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.sessionActive = false; self?.invalidate()
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.sessionActive = true; self?.frontChanged()
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.invalidate() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.invalidate() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.invalidate() }
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { [weak self] in self?.refreshPermissions() }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown,
                                             .flagsChanged, .keyDown, .keyUp, .scrollWheel]
        previousModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.observeHoldEvent(event)
        }
        mouseMonitorAvailable = mouseMonitor != nil
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            if event.type == .keyDown,
               NSApp.isActive, NSApp.modalWindow == nil,
               isCommandQuitShortcut(charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                     modifiers: event.modifierFlags) {
                self?.quit(); return nil
            }
            self?.observeHoldEvent(event)
            return event
        }
        KeyboardShortcuts.onKeyDown(for: .toggleFloatingInputBar) { [weak self] in self?.beginHold(.shortcut) }
        KeyboardShortcuts.onKeyUp(for: .toggleFloatingInputBar) { [weak self] in self?.releaseHold(.shortcut) }
        refreshPermissions(); frontChanged()
        // AX queries only on a trigger press and insertion; no focus polling.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        openSettings()
    }
    private func applyEntryVisibility() {
        let requestedDockVisible = entryVisibility.dock
        if dockPolicyChangeNeeded(currentDockVisible: NSApp.activationPolicy() == .regular,
                                  requestedDockVisible: requestedDockVisible) {
            _ = NSApp.setActivationPolicy(requestedDockVisible ? .regular : .accessory)
        }
        let actualDockVisible = NSApp.activationPolicy() == .regular
        if actualDockVisible != requestedDockVisible {
            if actualDockVisible {
                entryVisibility.setDock(true)
                notice = "Dock 图标仍然显示，菜单栏入口也已保留。"
            } else {
                entryVisibility.setMenuBar(true)
                entryVisibility.setDock(false)
                notice = "Dock 图标暂不可用，已保留菜单栏入口。"
            }
            entryVisibility.save()
        }
        if entryVisibility.menuBar {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "PhrasePerch")
            let menu = NSMenu()
            menu.addItem(withTitle: "启用／暂停", action: #selector(toggleEnabled), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "打开 PhrasePerch", action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(withTitle: "导入配置…", action: #selector(importConfiguration), keyEquivalent: "")
            menu.addItem(withTitle: "导出配置…", action: #selector(exportConfiguration), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
            for entry in menu.items { entry.target = self }
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }
    func setDockIconVisible(_ visible: Bool) {
        entryVisibility.setDock(visible)
        entryVisibility.save()
        applyEntryVisibility()
    }
    func setMenuBarIconVisible(_ visible: Bool) {
        entryVisibility.setMenuBar(visible)
        entryVisibility.save()
        applyEntryVisibility()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         callback: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { callback() }
        }
        observers.append((center, token))
    }
    private func tick() {
        if store.isReady, !readyWasSeen { readyWasSeen = true; frontChanged() }
        statusItem?.menu?.items.first?.state = store.configuration.preferences.isEnabled ? .on : .off
        if !store.configuration.preferences.isEnabled && !authorizationPending { invalidate() }
    }
    func refreshPermissions() {
        let previous = authorizationStatus
        let wasTrusted = accessibilityGranted
        let snapshot = authorizationEnvironment.snapshot()
        let trusted = snapshot.accessibility, events = snapshot.paste
        if (accessibilityGranted && !trusted || postEventsGranted && !events) { invalidate() }
        accessibilityGranted = trusted; postEventsGranted = events
        if authorizationStatus == .ready { stopAuthorizationWatch() }
        if authorizationStatus != previous {
            permissionFeedback = authorizationStatus == .ready ? "权限已就绪，可以使用快捷栏。" : "权限状态已更新。"
        }
        authorizationFlow.refresh(accessibility: trusted, paste: events)
        if (trusted && !wasTrusted) || authorizationStatus == .ready { authorizationGuide.hide() }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    private func stopAuthorizationWatch() {
        authorizationTask?.cancel(); authorizationTask = nil
        permissionTimer?.invalidate(); permissionTimer = nil
        authorizationPending = false
    }
    private func watchAuthorization() {
        guard authorizationStatus != .ready else { return }
        authorizationPending = true
        permissionDeadline = Date().addingTimeInterval(20)
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard Date() < self.permissionDeadline else {
                    self.permissionTimer?.invalidate(); self.permissionTimer = nil; return
                }
                self.refreshPermissions()
            }
        }
    }
    func performAuthorizationAction() {
        refreshPermissions()
        switch authorizationStep {
        case .authorize, .reauthorize: openAuthorizationSettings()
        case .restart: restartForAuthorization()
        case .ready: break
        }
    }
    func openAuthorizationSettings() {
        invalidate(); refreshPermissions()
        let opened = authorizationEnvironment.openSettings()
        permissionFeedback = opened
            ? "请在系统设置中添加并开启当前 PhrasePerch，然后返回应用重启。"
            : "无法打开授权页面。请手动打开系统设置的权限列表，添加并开启当前 PhrasePerch。"
        notice = permissionFeedback
        if opened {
            watchAuthorization()
            authorizationTask = Task { [weak self] in
                for _ in 0..<20 {
                    guard !Task.isCancelled else { return }
                    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences" { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard let self, !Task.isCancelled,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences",
                      authorizationStep == .authorize || authorizationStep == .reauthorize else { return }
                authorizationGuide.show(applicationURL: Bundle.main.bundleURL)
            }
        }
    }
    func restartForAuthorization() {
        guard !isRestarting else { return }
        guard store.isReady else {
            notice = "配置尚未正常加载，已取消重启。请先处理配置读取错误。"; return
        }
        invalidate(); isRestarting = true; permissionFeedback = "正在保存配置并重新启动…"
        Task {
            guard await authorizationEnvironment.save(store) else {
                isRestarting = false; notice = "配置未保存，已取消重启。请先处理保存错误。"; return
            }
            do {
                authorizationDefaults.set(Bundle.main.bundlePath, forKey: Self.restartPendingKey)
                try authorizationEnvironment.relaunch(Bundle.main.bundleURL, getpid())
                // Already saved: don't repeat an async save inside AppKit's nested termination loop.
                restartExitReady = true
                authorizationEnvironment.terminate()
            } catch {
                authorizationDefaults.removeObject(forKey: Self.restartPendingKey)
                isRestarting = false; notice = "重启失败：\(error.localizedDescription)。当前应用仍在运行。"
            }
        }
    }
    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { notice = "登录启动设置失败：\(error.localizedDescription)" }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func frontChanged() {
        let next = NSWorkspace.shared.frontmostApplication
        let checking = authorizationPending || authorizationGuide.isVisible
        refreshPermissions()
        if checking,
           next?.bundleIdentifier == "com.apple.systempreferences" || next?.bundleIdentifier == Bundle.main.bundleIdentifier {
            if authorizationPending { watchAuthorization() }
            target = next; return
        }
        if let target, next?.isEqual(target) == true, !target.isTerminated { return }
        invalidate(); target = next
    }
    private func invalidate() {
        stopAuthorizationWatch()
        authorizationGuide.hide()
        let captured = hold.id
        hold.cancel(); holdTask?.cancel(); holdTask = nil
        input.cancel(); floating.hide()
        if let captured { Task { await input.releaseTarget(captured) } }
    }
    func profile(for application: NSRunningApplication) -> AppProfile? {
        let identity = ApplicationIdentity(bundleIdentifier: application.bundleIdentifier,
                                            fallbackBundlePath: application.bundleURL?.path)
        return store.configuration.profiles.first { $0.application.key == identity.key }
    }
    private func isOwnShortcut(_ event: NSEvent) -> Bool {
        guard let recorded = KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar),
              let pressed = KeyboardShortcuts.Shortcut(event: event) else { return false }
        return recorded == pressed
    }
    private func observeHoldEvent(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == clipboardPasteEventTag { return }
        let relevant = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let previous = previousModifiers
        if event.type == .flagsChanged { previousModifiers = relevant }
        if authorizationPending, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences" {
            if event.type == .leftMouseUp { refreshPermissions(); watchAuthorization() }
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
                if relevant.isEmpty { releaseHold(.modifier) }
                else if relevant != modifier { invalidate() }
            } else if relevant == modifier && previous != modifier {
                beginHold(.modifier)
            }
        case .keyDown:
            if isOwnShortcut(event) { beginHold(.shortcut) }
            else if hold.id != nil { invalidate() }
        case .keyUp:
            if hold.trigger == .shortcut,
               Int(event.keyCode) == KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar)?.carbonKeyCode {
                releaseHold(.shortcut)
            }
        case .leftMouseDown:
            guard hold.id != nil else { return }
            let local = CGPoint(x: NSEvent.mouseLocation.x - floating.panel.frame.minX,
                                y: NSEvent.mouseLocation.y - floating.panel.frame.minY)
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
        frontChanged(); refreshPermissions()
        guard !isRestarting, sessionActive, store.isReady, store.configuration.preferences.isEnabled,
              authorizationStep == .ready, !input.isBusy, let target,
              target.bundleIdentifier != Bundle.main.bundleIdentifier,
              let profile = profile(for: target), profile.canTrigger(source),
              let token = hold.begin(source) else { return }
        let mouse = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let mode = store.configuration.preferences.menuAnchorMode
        let screens = NSScreen.screens.map(\.visibleFrame)
        holdTask = Task {
            let captured = await input.captureTarget(id: token, pid: target.processIdentifier,
                                                     mouse: mouse, primaryScreenTop: top, mode: mode)
            guard !Task.isCancelled, hold.isCurrent(token), let captured, captured.id == token, triggerIsHeld(source),
                  NSWorkspace.shared.frontmostApplication?.isEqual(target) == true else {
                await input.releaseTarget(token)
                if hold.isCurrent(token) {
                    notice = mode == .mouse ? "请先点入普通输入框，并将鼠标放在该输入框内。" : "请先点入普通输入框。"
                    invalidate()
                }
                return
            }
            let anchor = MenuAnchor(mode: mode, mouse: mouse, caretBounds: captured.caretBounds,
                                    primaryScreenTop: top, screens: screens)
            if anchor.usedMouseFallback { notice = "当前软件未提供有效光标位置，已改用鼠标位置展开。" }
            guard hold.show(token), floating.show(profile: profile, at: anchor.point,
                initialMouse: mouse, requiresMovement: mode == .caret) else {
                notice = floating.failureMessage
                invalidate(); return
            }
        }
    }
    private func triggerIsHeld(_ source: HoldMenuSession.Trigger) -> Bool {
        let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        if source == .modifier {
            return flags.rawValue == store.configuration.preferences.clickModifier.mask
        }
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar) else { return false }
        return flags == shortcut.modifiers.intersection([.command, .option, .control, .shift]) &&
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.carbonKeyCode))
    }
    private func releaseHold(_ source: HoldMenuSession.Trigger) {
        guard hold.trigger == source, hold.phase == .checking || hold.phase == .choosing else { return }
        let selected = floating.updateSelection(at: NSEvent.mouseLocation)
        let captured = hold.id
        guard let token = hold.release(source, selection: selected), let selected,
              let target, let profile = profile(for: target), profile.canTrigger(source),
              let snippet = profile.buttons.first(where: { $0.id == selected && $0.isEnabled }) else {
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
                if hold.isCurrent(token) { notice = "修饰键尚未松开，已取消粘贴。"; invalidate() }
                return
            }
            guard !Task.isCancelled, hold.commit(token) else { return }
            _ = await input.insert(snippet, target: target, sessionID: token)
            if hold.isCurrent(token) {
                notice = input.message
                hold.cancel(); holdTask = nil
            }
        }
    }
    @objc private func toggleEnabled() { store.configuration.preferences.isEnabled.toggle(); invalidate() }

    func addApplication(_ url: URL) {
        guard let bundle = Bundle(url: url), url.pathExtension == "app" else { notice = "请选择有效的 .app 应用包"; return }
        let identity = ApplicationIdentity(bundleIdentifier: bundle.bundleIdentifier, fallbackBundlePath: url.path)
        guard !store.configuration.profiles.contains(where: { $0.application.key == identity.key }) else { notice = "此应用已在列表中。"; return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        store.configuration.profiles.append(AppProfile(application: identity, displayName: name,
                                                       lastKnownBundlePath: url.path, buttons: [
            Snippet(title: "继续", text: "按照刚才确定的方案继续执行。"),
            Snippet(title: "检查", text: "请检查当前内容，指出遗漏、冲突和需要修改的地方。"),
            Snippet(title: "解释", text: "请解释其中的原理，并给出具体示例。")
        ]))
    }
    func chooseApplications() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(addApplication) }
    }
    @objc func openSettings() {
        invalidate()
        refreshPermissions()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 780),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "PhrasePerch"
            window.titleVisibility = .visible
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(coordinator: self))
            window.setContentSize(CGSize(width: 1180, height: 780))
            window.minSize = CGSize(width: 900, height: 600); window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func importConfiguration() {
        invalidate()
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let config = try await store.readImport(url)
                let alert = NSAlert(); alert.messageText = "替换现有配置？"
                alert.informativeText = "导入 \(config.profiles.count) 个应用、\(config.profiles.reduce(0) { $0 + $1.buttons.count }) 个按钮。替换前会备份现有配置。"
                alert.addButton(withTitle: "替换并备份"); alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn { await store.replace(with: config) }
            } catch { store.errorMessage = error.localizedDescription }
        }
    }
    @objc func exportConfiguration() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "PhrasePerch.json"
        if panel.runModal() == .OK, let url = panel.url { Task { await store.export(to: url) } }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func stop() {
        timer?.invalidate(); invalidate()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for (center, token) in observers { center.removeObserver(token) }
        KeyboardShortcuts.removeHandler(for: .toggleFloatingInputBar)
        KeyboardShortcuts.disable(.toggleFloatingInputBar)
    }
}
