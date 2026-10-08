import Foundation
import Observation

@MainActor @Observable
final class MainWindowViewModel {
    var page = MainPage.home
    private(set) var selectedProfile: UUID?
    private(set) var deleteProfile: UUID?
    var recoveryAlert = false
    private let repository: ConfigurationRepository
    private let editing: ProfileEditingService
    private let files: ConfigurationFileService
    private let authorization: AuthorizationService
    private var editors: [UUID: ProfileEditorViewModel] = [:]
    private var subscription: UUID?

    init(
        repository: ConfigurationRepository, editing: ProfileEditingService,
        files: ConfigurationFileService, authorization: AuthorizationService
    ) {
        self.repository = repository
        self.editing = editing
        self.files = files
        self.authorization = authorization
        reconcileProfiles()
        subscription = repository.observe { [weak self] in self?.reconcileProfiles() }
    }
    let applicationMetadata = ApplicationMetadata.current()
    var profiles: [AppProfile] { repository.configuration.profiles }
    var isReady: Bool { repository.isReady }
    var isRestarting: Bool { authorization.isRestarting }
    var loadIssue: ConfigurationIssue? { repository.issue }
    var deletionName: String { profiles.first { $0.id == deleteProfile }?.displayName ?? "" }
    var selectedEditor: ProfileEditorViewModel? { selectedProfile.flatMap { editors[$0] } }
    var runningApplications: [ApplicationChoice] { ApplicationCatalog.runningApplications() }
    func selectProfile(_ id: UUID) { if profiles.contains(where: { $0.id == id }) { selectedProfile = id } }
    func setEnabled(_ id: UUID, _ value: Bool) { editing.editProfile(id) { $0.isEnabled = value } }
    func requestDeletion(_ id: UUID) { if profiles.contains(where: { $0.id == id }) { deleteProfile = id } }
    func cancelDeletion() { deleteProfile = nil }
    func confirmDeletion(_ id: UUID) {
        guard deleteProfile == id else { return }
        editing.removeProfile(id)
        deleteProfile = nil
    }
    func requestRecovery() { recoveryAlert = true }
    func recover() { Task { await repository.restoreBackup() } }
    func chooseApplications() { files.chooseApplications() }
    func addApplication(_ url: URL) { files.addApplication(url) }
    func duplicateProfile(_ id: UUID) { files.duplicateProfile(id) }
    func openConfiguration() { page = .settings }
    func reconcileProfiles() {
        let ids = profiles.map(\.id)
        if selectedProfile == nil || !ids.contains(selectedProfile!) { selectedProfile = ids.first }
        for id in Array(editors.keys) where !ids.contains(id) { editors.removeValue(forKey: id)?.stop() }
        for id in ids where editors[id] == nil {
            let editor = ProfileEditorViewModel(profileID: id, repository: repository, editing: editing)
            editor.onOpenConfiguration = { [weak self] in self?.openConfiguration() }
            editors[id] = editor
        }
    }
    func stop() {
        if let subscription { repository.removeObserver(subscription) }
        subscription = nil
        for editor in editors.values { editor.stop() }
    }
}
