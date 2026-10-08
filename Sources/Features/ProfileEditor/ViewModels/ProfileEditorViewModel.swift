import Foundation
import Observation

@MainActor @Observable
final class ProfileEditorViewModel {
    let profileID: UUID
    private let repository: ConfigurationRepository
    private let editing: ProfileEditingService
    private let titleService: TitleGenerationService
    private var subscription: UUID?
    private var titleTask: Task<Void, Never>?
    private var titleGeneration = 0
    private var titleSnapshot: Snippet?
    private var titleSettings: (address: String, model: String)?
    private(set) var isGeneratingTitle = false
    private(set) var titleGenerationMessage: String?
    private(set) var session: SnippetEditorSession
    private(set) var deletionID: UUID?
    var showSaveIssue = false
    var onOpenConfiguration: (() -> Void)?

    init(
        profileID: UUID, repository: ConfigurationRepository, editing: ProfileEditingService,
        session: SnippetEditorSession = SnippetEditorSession(),
        titleService: TitleGenerationService = TitleGenerationService()
    ) {
        self.profileID = profileID
        self.repository = repository
        self.editing = editing
        self.titleService = titleService
        self.session = session
        reconcile()
        subscription = repository.observe { [weak self] in self?.reconcile() }
    }
    func stop() {
        cancelTitleGeneration()
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
    var canGenerateTitle: Bool {
        repository.isReady && !isGeneratingTitle
            && !repository.configuration.preferences.titleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedSnippet.map { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && SnippetValidator.textIssue($0.text) == nil } == true
    }
    var titleGenerationHelp: String {
        repository.configuration.preferences.titleModel.isEmpty
            ? "请先在设置中选择并保存标题生成模型。" : "根据正文生成4至6字的中文标题"
    }
    func title(_ id: UUID) -> String { profile?.buttons.first { $0.id == id }?.title ?? "" }
    func text(_ id: UUID) -> String { profile?.buttons.first { $0.id == id }?.text ?? "" }
    func setTitle(_ value: String, id: UUID) {
        if session.selectedID == id, title(id) != value { cancelTitleGeneration() }
        editing.editSnippet(profileID: profileID, snippetID: id) { $0.title = value }
    }
    func setText(_ value: String, id: UUID) {
        if session.selectedID == id, text(id) != value { cancelTitleGeneration() }
        editing.editSnippet(profileID: profileID, snippetID: id) { $0.text = value }
    }
    func select(_ id: UUID) {
        guard ids.contains(id) else { return }
        if session.selectedID != id { cancelTitleGeneration() }
        session.select(id, in: ids)
        showSaveIssue = false
    }
    func showPage(_ page: Int) {
        if session.page != page { cancelTitleGeneration() }
        session.showPage(page, in: ids)
        showSaveIssue = false
    }
    func reconcile() {
        session.reconcile(ids)
        if let snapshot = titleSnapshot {
            let preferences = repository.configuration.preferences
            if selectedSnippet?.id != snapshot.id || selectedSnippet?.title != snapshot.title
                || selectedSnippet?.text != snapshot.text || preferences.titleAPIBaseURL != titleSettings?.address
                || preferences.titleModel != titleSettings?.model
            { cancelTitleGeneration() }
        }
        if saveStatus != "保存失败" { showSaveIssue = false }
    }
    func generateTitle() {
        guard canGenerateTitle, let snippet = selectedSnippet else { return }
        cancelTitleGeneration()
        let token = titleGeneration
        let preferences = repository.configuration.preferences
        titleSnapshot = snippet
        titleSettings = (preferences.titleAPIBaseURL, preferences.titleModel)
        isGeneratingTitle = true
        titleTask = Task { [weak self, titleService] in
            do {
                let title = try await titleService.generateTitle(
                    for: snippet.text, address: preferences.titleAPIBaseURL, model: preferences.titleModel)
                guard let self, !Task.isCancelled, token == self.titleGeneration else { return }
                self.finishTitleGeneration()
                self.editing.editSnippet(profileID: self.profileID, snippetID: snippet.id) { $0.title = title }
            } catch {
                guard let self, !Task.isCancelled, token == self.titleGeneration else { return }
                self.finishTitleGeneration()
                if !(error is CancellationError) { self.titleGenerationMessage = error.localizedDescription }
            }
        }
    }
    func cancelTitleGeneration() {
        titleGeneration += 1
        titleTask?.cancel()
        finishTitleGeneration()
        titleGenerationMessage = nil
    }
    private func finishTitleGeneration() {
        titleTask = nil
        titleSnapshot = nil
        titleSettings = nil
        isGeneratingTitle = false
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
