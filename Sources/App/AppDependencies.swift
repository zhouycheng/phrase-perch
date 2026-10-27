import Foundation

@MainActor
final class AppDependencies {
    let repository: ConfigurationRepository
    let editing: ProfileEditingService
    let input: ContentInsertionService
    let floatingMenu: FloatingMenuWindowController
    let authorizationGuide: AuthorizationGuideWindowController
    let authorization: AuthorizationService
    let entry: AppEntryService
    let files: ConfigurationFileService
    let monitor: TriggerEventMonitor
    let runtime: TriggerSessionService
    let mainWindowViewModel: MainWindowViewModel
    let preferencesViewModel: PreferencesViewModel
    let mainWindow: MainWindowController

    init(
        repository: ConfigurationRepository? = nil,
        authorizationEnvironment: AuthorizationEnvironment = AuthorizationEnvironment(),
        defaults: UserDefaults = .standard,
        entryPlatform: any AppEntryPlatform = MacAppEntryController()
    ) {
        let repository = repository ?? ConfigurationRepository(initialConfiguration: ApplicationCatalog.initialConfiguration())
        self.repository = repository
        repository.clipboardFileURLs = { ClipboardService.fileURLs() }
        editing = ProfileEditingService(repository: repository)
        input = ContentInsertionService(retainAttachment: { try await repository.retainAttachment($0) },
            releaseAttachment: { await repository.releaseAttachment($0) })
        floatingMenu = FloatingMenuWindowController()
        authorizationGuide = AuthorizationGuideWindowController()
        authorization = AuthorizationService(
            store: repository, guide: authorizationGuide,
            environment: authorizationEnvironment, defaults: defaults)
        entry = AppEntryService(store: repository, platform: entryPlatform, defaults: defaults)
        files = ConfigurationFileService(store: repository, editing: editing, dialog: MacConfigurationFileDialog())
        monitor = TriggerEventMonitor()
        runtime = TriggerSessionService(
            store: repository, input: input, floating: floatingMenu,
            authorization: authorization, monitor: monitor, entry: entry)
        mainWindowViewModel = MainWindowViewModel(
            repository: repository, editing: editing, files: files, authorization: authorization)
        preferencesViewModel = PreferencesViewModel(
            repository: repository, service: PreferencesService(repository: repository),
            authorization: authorization, entry: entry, files: files,
            monitorAvailable: { [monitor] in monitor.mouseMonitorAvailable },
            diagnostics: runtime.diagnostics, shortcutState: { [monitor] in monitor.shortcutStatus })
        mainWindow = MainWindowController(viewModel: mainWindowViewModel, preferences: preferencesViewModel)
        mainWindow.onClose = { [weak entry] in entry?.setMainWindowOpen(false) }
        authorization.onInvalidate = { [weak runtime] in runtime?.invalidate() }
        files.onInvalidate = { [weak runtime] in runtime?.invalidate() }
    }
}
