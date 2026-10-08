import Foundation

@MainActor
final class AppDependencies {
    let repository: ConfigurationRepository
    let editing: ProfileEditingService
    let titles: TitleGenerationService
    let input: TextInsertionService
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
        repository: ConfigurationRepository = ConfigurationRepository(),
        authorizationEnvironment: AuthorizationEnvironment = AuthorizationEnvironment(),
        defaults: UserDefaults = .standard,
        titleService: TitleGenerationService = TitleGenerationService()
    ) {
        self.repository = repository
        editing = ProfileEditingService(repository: repository)
        titles = titleService
        input = TextInsertionService()
        floatingMenu = FloatingMenuWindowController()
        authorizationGuide = AuthorizationGuideWindowController()
        authorization = AuthorizationService(
            store: repository, guide: authorizationGuide,
            environment: authorizationEnvironment, defaults: defaults)
        entry = AppEntryService(store: repository)
        files = ConfigurationFileService(store: repository, editing: editing, dialog: MacConfigurationFileDialog())
        monitor = TriggerEventMonitor()
        runtime = TriggerSessionService(
            store: repository, input: input, floating: floatingMenu,
            authorization: authorization, monitor: monitor, entry: entry)
        mainWindowViewModel = MainWindowViewModel(
            repository: repository, editing: editing, files: files, authorization: authorization, titleService: titles)
        preferencesViewModel = PreferencesViewModel(
            repository: repository, service: PreferencesService(repository: repository),
            authorization: authorization, entry: entry, files: files,
            monitorAvailable: { [monitor] in monitor.mouseMonitorAvailable }, titleService: titles)
        mainWindow = MainWindowController(viewModel: mainWindowViewModel, preferences: preferencesViewModel)
        authorization.onInvalidate = { [weak runtime] in runtime?.invalidate() }
        files.onInvalidate = { [weak runtime] in runtime?.invalidate() }
    }
}
