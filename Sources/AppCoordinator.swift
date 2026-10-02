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

@MainActor @Observable
final class AppCoordinator: NSObject {
    let store = ConfigurationStore()
    let input = TextInsertionService()
    private(set) var accessibilityGranted = false
    private(set) var postEventsGranted = false
    private(set) var permissionFeedback = ""
    private(set) var isRestarting = false
    private(set) var restartExitReady = false
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
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var target: NSRunningApplication?
    private var dismissed = false
    private var sessionActive = true
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var mouseMonitor: Any?
    private var localMonitor: Any?
    private var clickGesture: ModifierGesture?
    private var gestureID: UUID?
    private var gestureCapture: Task<Bool, Never>?
    private var timer: Timer?
    private var readyWasSeen = false
    private var panelVersion = 0
    private var authorizationOpening = false
    private var authorizationPending = false
    private var permissionTimer: Timer?
    private var permissionDeadline = Date.distantPast

    override init() {
        super.init()
        store.onChange = { [weak self] in self?.invalidate() }
        floating.onInsert = { [weak self] id in self?.insert(id) }
        floating.onDismiss = { [weak self] in
            self?.dismissed = true; self?.invalidate()
        }
        floating.onAuthorizationAction = { [weak self] action in
            switch action {
            case .restart: self?.restartForAuthorization()
            case .settings: self?.openAuthorizationSettings()
            }
        }
        floating.onApplicationDragEnded = { [weak self] accepted in
            guard let self else { return }
            permissionFeedback = accepted ? "已加入系统列表，请开启 PhrasePerch 的开关。" : "未接受拖入，请重试。"
            refreshPermissions()
            watchAuthorization()
        }
        floating.isOwnShortcut = { event in
            guard let recorded = KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar),
                  let pressed = KeyboardShortcuts.Shortcut(event: event) else { return false }
            return recorded == pressed
        }
        floating.shortcutModifiers = {
            KeyboardShortcuts.getShortcut(for: .toggleFloatingInputBar)?.modifiers ?? []
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
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged, .leftMouseDown, .flagsChanged]) { [weak self] event in
            self?.observeMouseGesture(event)
        }
        mouseMonitorAvailable = mouseMonitor != nil
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .flagsChanged]) { [weak self] event in
            if event.type == .flagsChanged { self?.clickGesture?.observe(flags: event.modifierFlags.rawValue) }
            else if let self, event.window !== self.floating.panel { self.invalidate() }
            return event
        }
        KeyboardShortcuts.onKeyUp(for: .toggleFloatingInputBar) { [weak self] in self?.togglePanel() }
        refreshPermissions(); frontChanged()
        // AX queries only on editor clicks, explicit shortcuts, and insertion; no focus polling.
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
            menu.addItem(withTitle: "显示／收起快捷栏", action: #selector(togglePanel), keyEquivalent: "")
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
        if !store.configuration.preferences.isEnabled && !floating.isAuthorization && !authorizationPending { invalidate() }
    }
    func refreshPermissions() {
        let previous = authorizationStatus
        let trusted = AXIsProcessTrusted(), events = CGPreflightPostEventAccess()
        if (accessibilityGranted && !trusted || postEventsGranted && !events) && !floating.isAuthorization { invalidate() }
        accessibilityGranted = trusted; postEventsGranted = events
        if authorizationStatus == .ready { stopAuthorizationWatch() }
        if authorizationStatus != previous {
            permissionFeedback = authorizationStatus == .ready ? "权限检查通过，自动粘贴已可用。" : "权限状态已更新。"
        }
        if floating.isAuthorization {
            floating.updateAuthorization(status: authorizationStatus, feedback: permissionFeedback)
            if authorizationStatus == .ready { floating.hide() }
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    private func stopAuthorizationWatch() {
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
    func openAuthorizationSettings() {
        invalidate(); refreshPermissions()
        authorizationOpening = true
        let opened = NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        permissionFeedback = opened
            ? "将图标拖入应用列表，再开启 PhrasePerch 的开关。权限会自动检查。"
            : "未能打开授权页面。请从苹果菜单打开系统设置 → 隐私与安全性，找到应用控制权限。"
        refreshPermissions()
        let version = panelVersion
        Task {
            // System Settings opens asynchronously; bounded wait uses window metadata, not AX permission.
            for _ in 0..<20 {
                guard version == panelVersion else { return }
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences" { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard version == panelVersion else { return }
            authorizationOpening = false
            guard opened, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences" else {
                notice = "未能打开系统授权页面，请重试。"; return
            }
            if authorizationStatus != .ready {
                floating.showAuthorization(status: authorizationStatus, feedback: permissionFeedback,
                                           applicationURL: Bundle.main.bundleURL)
                watchAuthorization()
            }
        }
    }
    func requestPasteAuthorization() {
        refreshPermissions()
        guard !postEventsGranted else { return }
        _ = CGRequestPostEventAccess()
        refreshPermissions()
        permissionFeedback = postEventsGranted ? "粘贴输入已授权。" : "等待系统确认粘贴输入权限。"
        notice = permissionFeedback
        watchAuthorization()
    }
    func restartForAuthorization() {
        guard !isRestarting else { return }
        guard store.isReady else {
            notice = "配置尚未正常加载，已取消重启。请先处理配置读取错误。"; return
        }
        invalidate(); isRestarting = true; permissionFeedback = "正在保存配置并重新启动…"
        Task {
            guard await store.flush() else {
                isRestarting = false; notice = "配置未保存，已取消重启。请先处理保存错误。"; return
            }
            do {
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                // Wait for this process to exit before reopening, so two window sets never coexist.
                let script = """
                restart_checks=0
                while kill -0 "$1" 2>/dev/null; do
                    restart_checks=$((restart_checks + 1))
                    [ "$restart_checks" -lt 100 ] || exit 1
                    sleep 0.1
                done
                exec /usr/bin/open "$2"
                """
                relaunch.arguments = ["-c", script, "PhrasePerchRestart", String(getpid()), Bundle.main.bundlePath]
                relaunch.standardOutput = FileHandle.nullDevice
                relaunch.standardError = FileHandle.nullDevice
                try relaunch.run()
                // Already saved: don't repeat an async save inside AppKit's nested termination loop.
                restartExitReady = true
                NSApp.terminate(nil)
            } catch {
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
        let checking = authorizationOpening || floating.isAuthorization || authorizationPending
        refreshPermissions()
        if checking,
           next?.bundleIdentifier == "com.apple.systempreferences" || next?.bundleIdentifier == Bundle.main.bundleIdentifier {
            if authorizationPending { watchAuthorization() }
            target = next; return
        }
        if let target, next?.isEqual(target) == true, !target.isTerminated { return }
        invalidate(); target = next; dismissed = false
    }
    private func invalidate() {
        authorizationOpening = false
        stopAuthorizationWatch()
        panelVersion += 1; clickGesture = nil; gestureID = nil; gestureCapture?.cancel(); gestureCapture = nil
        input.cancel(); floating.hide()
    }
    func profile(for application: NSRunningApplication) -> AppProfile? {
        let identity = ApplicationIdentity(bundleIdentifier: application.bundleIdentifier,
                                            fallbackBundlePath: application.bundleURL?.path)
        return store.configuration.profiles.first { $0.application.key == identity.key }
    }
    private func observeMouseGesture(_ event: NSEvent) {
        if authorizationPending, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences" {
            if event.type == .leftMouseUp { refreshPermissions(); watchAuthorization() }
            return
        }
        if authorizationOpening || floating.isAuthorization { return }
        if event.type == .flagsChanged {
            clickGesture?.observe(flags: event.modifierFlags.rawValue)
            return
        }
        if event.type == .leftMouseDown {
            frontChanged(); invalidate()
            refreshPermissions()
            let state = ModifierGesture(modifier: store.configuration.preferences.clickModifier,
                                        flags: event.modifierFlags.rawValue)
            guard state.valid, !input.isBusy, accessibilityGranted, sessionActive, store.isReady,
                  store.configuration.preferences.isEnabled, let target,
                  let profile = profile(for: target), profile.isEnabled,
                  profile.displayMode == .modifierClick else { return }
            let id = UUID(), mouse = NSEvent.mouseLocation
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            clickGesture = state; gestureID = id
            gestureCapture = Task { await input.captureGesture(id: id, pid: target.processIdentifier,
                                                              mouse: mouse, primaryScreenTop: top) }
        } else if event.type == .leftMouseDragged {
            clickGesture?.dragged = true
            clickGesture?.observe(flags: event.modifierFlags.rawValue)
        } else {
            guard var state = clickGesture, let id = gestureID, let capture = gestureCapture,
                  let target, let profile = profile(for: target) else { return }
            state.observe(flags: event.modifierFlags.rawValue)
            clickGesture = nil; gestureID = nil; gestureCapture = nil
            guard state.valid else { return }
            let version = panelVersion, mouse = NSEvent.mouseLocation
            Task {
                guard await capture.value, panelVersion == version else { return }
                // The editor gets the mouse-up before the AX selection check; never write or alter the selection.
                try? await Task.sleep(for: .milliseconds(40))
                guard panelVersion == version,
                      await input.finishGesture(id: id, pid: target.processIdentifier, state: state),
                      panelVersion == version,
                      NSWorkspace.shared.frontmostApplication?.isEqual(target) == true else { return }
                dismissed = false
                show(profile, at: mouse)
            }
        }
    }
    private func show(_ profile: AppProfile, at anchor: CGPoint? = nil) {
        refreshPermissions()
        guard !isRestarting, sessionActive, store.isReady, store.configuration.preferences.isEnabled,
              accessibilityGranted, profile.isEnabled, !dismissed, !input.isBusy,
              profile.buttons.contains(where: \.isEnabled), let target,
              target.bundleIdentifier != Bundle.main.bundleIdentifier,
              NSWorkspace.shared.frontmostApplication?.isEqual(target) == true else { floating.hide(); return }
        let version = panelVersion
        let mouse = anchor ?? NSEvent.mouseLocation
        Task {
            guard await input.canShowMenu(pid: target.processIdentifier),
                  panelVersion == version, !input.isBusy, !dismissed,
                  NSWorkspace.shared.frontmostApplication?.isEqual(target) == true else { return }
            panelVersion += 1
            floating.show(profile: profile, at: mouse)
        }
    }
    @objc func togglePanel() {
        if floating.isPresented { dismissed = true; invalidate(); return }
        target = NSWorkspace.shared.frontmostApplication; dismissed = false
        guard let target, let profile = profile(for: target) else { notice = "当前应用未配置，请在设置中添加"; return }
        show(profile)
    }
    @objc private func toggleEnabled() { store.configuration.preferences.isEnabled.toggle(); invalidate() }

    func addApplication(_ url: URL) {
        guard let bundle = Bundle(url: url), url.pathExtension == "app" else { notice = "请选择有效的 .app 应用包"; return }
        let identity = ApplicationIdentity(bundleIdentifier: bundle.bundleIdentifier, fallbackBundlePath: url.path)
        guard !store.configuration.profiles.contains(where: { $0.application.key == identity.key }) else { notice = "该应用已添加；相同 Bundle Identifier 共享规则"; return }
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
    private func insert(_ id: UUID) {
        guard !isRestarting, !input.isBusy, let target, let profile = profile(for: target), profile.isEnabled,
              store.configuration.preferences.isEnabled,
              let snippet = profile.buttons.first(where: { $0.id == id && $0.isEnabled }) else { return }
        guard NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
            floating.updateStatus("请先松开修饰键", busy: false)
            return
        }
        floating.updateStatus("正在输入…", busy: true)
        let versionOfPanel = panelVersion
        Task {
            let result = await input.insert(snippet, target: target)
            notice = input.message
            if panelVersion == versionOfPanel { floating.updateStatus(input.message, busy: false) }
            if panelVersion == versionOfPanel && result.closesMenu && floating.isPresented {
                floating.hide()
            }
        }
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
        KeyboardShortcuts.disable(.toggleFloatingInputBar)
    }
}
