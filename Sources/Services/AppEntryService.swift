import Foundation
import Observation

@MainActor @Observable
final class AppEntryService {
    private(set) var entryVisibility = AppEntryPreferencesStorage.load()
    var dockIconVisible: Bool { entryVisibility.dock }
    var menuBarIconVisible: Bool { entryVisibility.menuBar }
    private(set) var loginEnabled: Bool
    var notice = ""
    private let platform: any AppEntryPlatform
    private let store: ConfigurationRepository
    var onOpen: (() -> Void)?
    var onImport: (() -> Void)?
    var onExport: (() -> Void)?
    init(store: ConfigurationRepository, platform: any AppEntryPlatform = MacAppEntryController()) {
        self.store = store
        self.platform = platform
        loginEnabled = platform.loginEnabled
    }
    func start() { applyEntryVisibility() }
    func refresh() {
        loginEnabled = platform.loginEnabled
        platform.refreshMenu(enabled: store.configuration.preferences.isEnabled)
    }
    func stop() { platform.stop() }
    private func applyEntryVisibility() {
        let requestedDockVisible = entryVisibility.dock
        if dockPolicyChangeNeeded(
            currentDockVisible: platform.dockVisible,
            requestedDockVisible: requestedDockVisible)
        {
            platform.setDockVisible(requestedDockVisible)
        }
        let actualDockVisible = platform.dockVisible
        if actualDockVisible != requestedDockVisible {
            if actualDockVisible {
                entryVisibility.setDock(true)
                notice = "Dock 图标仍然显示，菜单栏入口也已保留。"
            } else {
                entryVisibility.setMenuBar(true)
                entryVisibility.setDock(false)
                notice = "Dock 图标暂不可用，已保留菜单栏入口。"
            }
            AppEntryPreferencesStorage.save(entryVisibility)
        }

        platform.setMenuBar(
            visible: entryVisibility.menuBar, enabled: store.configuration.preferences.isEnabled,
            toggle: { [weak self] in self?.store.update { $0.preferences.isEnabled.toggle() } },
            open: { [weak self] in self?.onOpen?() }, importFile: { [weak self] in self?.onImport?() },
            exportFile: { [weak self] in self?.onExport?() })
    }
    func setDockIconVisible(_ visible: Bool) {
        entryVisibility.setDock(visible)
        AppEntryPreferencesStorage.save(entryVisibility)
        applyEntryVisibility()
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        entryVisibility.setMenuBar(visible)
        AppEntryPreferencesStorage.save(entryVisibility)
        applyEntryVisibility()
    }
    func setLoginEnabled(_ enabled: Bool) {
        do { try platform.setLoginEnabled(enabled) } catch { notice = "登录启动设置失败：\(error.localizedDescription)" }
        loginEnabled = platform.loginEnabled
    }
}
