import Foundation
import Observation

@MainActor @Observable
final class AppEntryService {
    private(set) var entryVisibility: AppEntryVisibility
    var dockIconVisible: Bool { entryVisibility.dock }
    var menuBarIconVisible: Bool { entryVisibility.menuBar }
    private(set) var loginEnabled: Bool
    private(set) var silentLaunchEnabled: Bool
    private(set) var isMainWindowOpen = false
    var notice = ""
    private let platform: any AppEntryPlatform
    private let store: ConfigurationRepository
    private let defaults: UserDefaults
    var onOpen: (() -> Void)?
    var onImport: (() -> Void)?
    var onExport: (() -> Void)?
    init(store: ConfigurationRepository, platform: any AppEntryPlatform = MacAppEntryController(),
        defaults: UserDefaults = .standard) {
        self.store = store
        self.platform = platform
        self.defaults = defaults
        entryVisibility = AppEntryPreferencesStorage.load(from: defaults)
        silentLaunchEnabled = AppEntryPreferencesStorage.loadSilentLaunch(from: defaults)
        loginEnabled = platform.loginEnabled
    }
    func shouldOpenMainWindow(launchedAtLogin: Bool) -> Bool { !launchedAtLogin || !silentLaunchEnabled }
    func setMainWindowOpen(_ open: Bool) {
        isMainWindowOpen = open
        applyEntryVisibility()
    }
    func start() { applyEntryVisibility() }
    func refresh() {
        loginEnabled = platform.loginEnabled
        platform.refreshMenu(enabled: store.configuration.preferences.isEnabled)
    }
    func stop() { platform.stop() }
    private func applyEntryVisibility() {
        notice = ""
        let requestedDockVisible = isMainWindowOpen || entryVisibility.dock
        if dockPolicyChangeNeeded(
            currentDockVisible: platform.dockVisible,
            requestedDockVisible: requestedDockVisible)
        {
            platform.setDockVisible(requestedDockVisible)
        }
        let actualDockVisible = platform.dockVisible
        if actualDockVisible != requestedDockVisible {
            if actualDockVisible {
                notice = "Dock 图标暂时无法隐藏，菜单栏入口仍可使用。"
            } else {
                notice = "Dock 图标暂不可用，已保留菜单栏入口。"
            }
        }

        platform.setMenuBar(
            visible: entryVisibility.menuBar || !actualDockVisible, enabled: store.configuration.preferences.isEnabled,
            toggle: { [weak self] in self?.store.update { $0.preferences.isEnabled.toggle() } },
            open: { [weak self] in self?.onOpen?() }, importFile: { [weak self] in self?.onImport?() },
            exportFile: { [weak self] in self?.onExport?() })
    }
    func setDockIconVisible(_ visible: Bool) {
        entryVisibility.setDock(visible)
        AppEntryPreferencesStorage.save(entryVisibility, to: defaults)
        applyEntryVisibility()
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        entryVisibility.setMenuBar(visible)
        AppEntryPreferencesStorage.save(entryVisibility, to: defaults)
        applyEntryVisibility()
    }
    func setLoginEnabled(_ enabled: Bool) {
        notice = ""
        do { try platform.setLoginEnabled(enabled) } catch { notice = "登录启动设置失败：\(error.localizedDescription)" }
        loginEnabled = platform.loginEnabled
    }
    func setSilentLaunchEnabled(_ enabled: Bool) {
        silentLaunchEnabled = enabled
        AppEntryPreferencesStorage.saveSilentLaunch(enabled, to: defaults)
    }
}
