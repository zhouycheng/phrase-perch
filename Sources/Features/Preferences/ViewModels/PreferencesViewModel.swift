import Foundation
import Observation

@MainActor @Observable
final class PreferencesViewModel {
    private let repository: ConfigurationRepository
    private let service: PreferencesService
    private let authorization: AuthorizationService
    private let entry: AppEntryService
    private let files: ConfigurationFileService
    private let monitorAvailable: () -> Bool
    private let titleService: TitleGenerationService
    private var modelsTask: Task<Void, Never>?
    private var modelsGeneration = 0
    var titleAPIBaseURL = Preferences.defaultTitleAPIBaseURL {
        didSet {
            if titleAPIBaseURL != oldValue {
                cancelModelsRead()
                titleModels = []
                titleSettingsMessage = nil
            }
        }
    }
    var titleModel = ""
    private(set) var titleModels: [String] = []
    private(set) var isReadingModels = false
    private(set) var isSavingTitleSettings = false
    private(set) var titleSettingsMessage: String?
    init(
        repository: ConfigurationRepository, service: PreferencesService, authorization: AuthorizationService,
        entry: AppEntryService, files: ConfigurationFileService, monitorAvailable: @escaping () -> Bool,
        titleService: TitleGenerationService = TitleGenerationService()
    ) {
        self.repository = repository
        self.service = service
        self.authorization = authorization
        self.entry = entry
        self.files = files
        self.monitorAvailable = monitorAvailable
        self.titleService = titleService
    }
    var isReady: Bool { repository.isReady }
    var issue: ConfigurationIssue? { repository.issue }
    var validationMessage: String? { repository.validationMessage }
    var enabled: Bool {
        get { repository.configuration.preferences.isEnabled }
        set { service.update { $0.isEnabled = newValue } }
    }
    var clickModifier: ClickModifier {
        get { repository.configuration.preferences.clickModifier }
        set { service.update { $0.clickModifier = newValue } }
    }
    var menuAnchorMode: MenuAnchorMode {
        get { repository.configuration.preferences.menuAnchorMode }
        set { service.update { $0.menuAnchorMode = newValue } }
    }
    var authorizationStep: AuthorizationFlow.Step { authorization.authorizationStep }
    var authorizationDetail: String { authorization.authorizationDetail }
    var isRestarting: Bool { authorization.isRestarting }
    var mouseMonitorAvailable: Bool { monitorAvailable() }
    var loginEnabled: Bool {
        get { entry.loginEnabled }
        set { entry.setLoginEnabled(newValue) }
    }
    var dockIconVisible: Bool {
        get { entry.dockIconVisible }
        set { entry.setDockIconVisible(newValue) }
    }
    var menuBarIconVisible: Bool {
        get { entry.menuBarIconVisible }
        set { entry.setMenuBarIconVisible(newValue) }
    }
    func performAuthorizationAction() { authorization.performAuthorizationAction() }
    func importConfiguration() { files.importConfiguration() }
    func exportConfiguration() { files.exportConfiguration() }
    func retryLoad() { Task { await repository.retryLoad() } }
    func retrySave() { Task { _ = await repository.flush() } }
    func loadTitleSettings() {
        guard isReady else { return }
        titleAPIBaseURL = repository.configuration.preferences.titleAPIBaseURL
        titleModel = repository.configuration.preferences.titleModel
        titleSettingsMessage = nil
    }
    func readTitleModels() {
        guard !isReadingModels else { return }
        cancelModelsRead()
        let token = modelsGeneration
        let address = titleAPIBaseURL
        titleSettingsMessage = nil
        isReadingModels = true
        modelsTask = Task { [weak self, titleService] in
            do {
                let models = try await titleService.models(at: address)
                guard let self, !Task.isCancelled, token == self.modelsGeneration else { return }
                self.titleModels = models
                self.isReadingModels = false
                self.modelsTask = nil
            } catch {
                guard let self, !Task.isCancelled, token == self.modelsGeneration else { return }
                self.isReadingModels = false
                self.modelsTask = nil
                if !(error is CancellationError) { self.titleSettingsMessage = error.localizedDescription }
            }
        }
    }
    func cancelModelsRead() {
        modelsGeneration += 1
        modelsTask?.cancel()
        modelsTask = nil
        isReadingModels = false
    }
    func saveTitleSettings() async {
        guard isReady, !isSavingTitleSettings else { return }
        do {
            let address = try TitleGenerationService.baseURL(titleAPIBaseURL).absoluteString
            let model = titleModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { throw InputFailure("请先读取模型并选择标题生成模型。") }
            isSavingTitleSettings = true
            defer { isSavingTitleSettings = false }
            service.update { $0.titleAPIBaseURL = address; $0.titleModel = model }
            let saved = await repository.flush()
            titleSettingsMessage = saved ? "设置已保存" : "设置已应用，配置尚未保存：\(repository.errorMessage ?? repository.saveStatus)"
        } catch { titleSettingsMessage = error.localizedDescription }
    }
}
