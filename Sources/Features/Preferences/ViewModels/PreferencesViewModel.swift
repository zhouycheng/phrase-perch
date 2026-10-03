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
    init(
        repository: ConfigurationRepository, service: PreferencesService, authorization: AuthorizationService,
        entry: AppEntryService, files: ConfigurationFileService, monitorAvailable: @escaping () -> Bool
    ) {
        self.repository = repository
        self.service = service
        self.authorization = authorization
        self.entry = entry
        self.files = files
        self.monitorAvailable = monitorAvailable
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
}
