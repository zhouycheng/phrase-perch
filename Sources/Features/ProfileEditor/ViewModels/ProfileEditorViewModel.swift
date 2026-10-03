import Foundation
import Observation

@MainActor @Observable
final class ProfileEditorViewModel {
    let profileID: UUID
    private let repository: ConfigurationRepository
    private let editing: ProfileEditingService
    private var subscription: UUID?
    private(set) var session: SnippetEditorSession
    private(set) var deletionID: UUID?
    var showSaveIssue = false
    var onOpenConfiguration: (() -> Void)?

    init(
        profileID: UUID, repository: ConfigurationRepository, editing: ProfileEditingService,
        session: SnippetEditorSession = SnippetEditorSession()
    ) {
        self.profileID = profileID
        self.repository = repository
        self.editing = editing
        self.session = session
        reconcile()
        subscription = repository.observe { [weak self] in self?.reconcile() }
    }
    func stop() {
        if let subscription { repository.removeObserver(subscription) }
        subscription = nil
    }
    var profile: AppProfile? { repository.configuration.profiles.first { $0.id == profileID } }
    var ids: [UUID] { profile?.buttons.map(\.id) ?? [] }
    var displayName: String { profile?.displayName ?? "" }
    var displayMode: DisplayMode {
        get { profile?.displayMode ?? .modifierClick }
        set { editing.editProfile(profileID) { $0.displayMode = newValue } }
    }
    var pages: Int { SnippetEditorSession.pageCount(ids.count) }
    var visibleSnippets: [Snippet] {
        Array(
            (profile?.buttons ?? []).dropFirst(session.page * SnippetEditorSession.pageSize).prefix(
                SnippetEditorSession.pageSize))
    }
    var selectedSnippet: Snippet? { profile?.buttons.first { $0.id == session.selectedID } }
    var saveStatus: String { repository.saveStatus }
    var configurationIssue: ConfigurationIssue? { repository.saveIssue }
    var titleIssue: String? { selectedSnippet.flatMap { SnippetValidator.titleIssue($0.title) } }
    var textIssue: String? { selectedSnippet.flatMap { SnippetValidator.textIssue($0.text) } }
    func title(_ id: UUID) -> String { profile?.buttons.first { $0.id == id }?.title ?? "" }
    func text(_ id: UUID) -> String { profile?.buttons.first { $0.id == id }?.text ?? "" }
    func setTitle(_ value: String, id: UUID) {
        editing.editSnippet(profileID: profileID, snippetID: id) { $0.title = value }
    }
    func setText(_ value: String, id: UUID) {
        editing.editSnippet(profileID: profileID, snippetID: id) { $0.text = value }
    }
    func select(_ id: UUID) {
        guard ids.contains(id) else { return }
        session.select(id, in: ids)
        showSaveIssue = false
    }
    func showPage(_ page: Int) {
        session.showPage(page, in: ids)
        showSaveIssue = false
    }
    func reconcile() {
        session.reconcile(ids)
        if saveStatus != "保存失败" { showSaveIssue = false }
    }
    func addSnippet() { if let id = editing.addSnippet(to: profileID) { select(id) } }
    func duplicate(_ id: UUID) { if let created = editing.duplicateSnippet(id, in: profileID) { select(created) } }
    func move(_ id: UUID, by distance: Int) {
        editing.moveSnippet(id, in: profileID, by: distance)
        select(id)
    }
    func requestDeletion(_ id: UUID) { if ids.contains(id) { deletionID = id } }
    func cancelDeletion() { deletionID = nil }
    func confirmDeletion(_ id: UUID) {
        guard deletionID == id else { return }
        deletionID = nil
        if let index = editing.removeSnippet(id, in: profileID) { session.deleted(at: index, remaining: ids) }
    }
    func retrySave() { Task { _ = await repository.flush() } }
    func openConfiguration() {
        showSaveIssue = false
        onOpenConfiguration?()
    }
}
