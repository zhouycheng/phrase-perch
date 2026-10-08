import AppKit

@MainActor
final class ApplicationCoordinator {
    let dependencies: AppDependencies
    var store: ConfigurationRepository { dependencies.repository }
    var mainWindowViewModel: MainWindowViewModel { dependencies.mainWindowViewModel }
    var preferencesViewModel: PreferencesViewModel { dependencies.preferencesViewModel }
    var restartExitReady: Bool { dependencies.authorization.restartExitReady }
    init(dependencies: AppDependencies = AppDependencies()) { self.dependencies = dependencies }
    func start() {
        dependencies.entry.onOpen = { [weak self] in self?.openMainWindow() }
        dependencies.entry.onImport = { [weak self] in self?.dependencies.files.importConfiguration() }
        dependencies.entry.onExport = { [weak self] in self?.dependencies.files.exportConfiguration() }
        dependencies.entry.start()
        dependencies.runtime.start()
        openMainWindow()
    }
    func openMainWindow() {
        dependencies.runtime.invalidate()
        dependencies.authorization.refreshPermissions()
        dependencies.mainWindow.open()
    }
    func stop() {
        dependencies.runtime.stop()
        dependencies.entry.stop()
        dependencies.mainWindowViewModel.stop()
        dependencies.preferencesViewModel.cancelModelsRead()
    }
}
