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
    private(set) var groupPath: [UUID] = []
    var currentGroup: UUID? { groupPath.last }
    var nodes: [MenuNode] { profile?.children(of: currentGroup) ?? [] }
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
    var ids: [UUID] { nodes.filter { $0.kind == .snippet }.map(\.id) }
    var displayName: String { profile?.displayName ?? "" }
    var displayMode: DisplayMode {
        get { profile?.displayMode ?? .modifierClick }
        set { editing.editProfile(profileID) { $0.displayMode = newValue } }
    }
    func toggleModifierTrigger() {
        switch displayMode {
        case .modifierClick: break
        case .shortcutOnly: displayMode = .both
        case .both: displayMode = .shortcutOnly
        }
    }
    func toggleShortcutTrigger() {
        switch displayMode {
        case .modifierClick: displayMode = .both
        case .shortcutOnly: break
        case .both: displayMode = .modifierClick
        }
    }
    var pages: Int { SnippetEditorSession.pageCount(ids.count) }
    var visibleSnippets: [Snippet] {
        Array(
            ids.compactMap { id in profile?.buttons.first { $0.id == id } }.dropFirst(session.page * SnippetEditorSession.pageSize).prefix(
                SnippetEditorSession.pageSize))
    }
    var selectedSnippet: Snippet? { profile?.buttons.first { $0.id == session.selectedID } }
    var hierarchyIssue: String? { repository.validationMessage ?? repository.saveIssue?.message }
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
        if let invalid = groupPath.firstIndex(where: { id in profile?.groups.contains(where: { $0.id == id }) != true }) {
            groupPath.removeSubrange(invalid...)
        }
        session.reconcile(ids)
        if saveStatus != "保存失败" { showSaveIssue = false }
    }
    func openGroup(_ id: UUID?) {
        if let id {
            if let index = groupPath.firstIndex(of: id) { groupPath = Array(groupPath.prefix(index + 1)) }
            else if nodes.contains(MenuNode(kind: .group, id: id)) { groupPath.append(id) }
        } else { groupPath = [] }
        session = SnippetEditorSession()
        reconcile()
    }
    func addGroup() { editing.addGroup(to: profileID, parent: currentGroup) }
    func groupTitle(_ id: UUID) -> String { profile?.groups.first { $0.id == id }?.title ?? "" }
    func setGroupTitle(_ title: String, id: UUID) { editing.editGroup(id, in: profileID) { $0.title = title } }
    func isEnabled(_ node: MenuNode) -> Bool {
        if node.kind == .group { return profile?.groups.first { $0.id == node.id }?.isEnabled ?? false }
        return profile?.buttons.first { $0.id == node.id }?.isEnabled ?? false
    }
    func setEnabled(_ enabled: Bool, node: MenuNode) {
        if node.kind == .group { editing.editGroup(node.id, in: profileID) { $0.isEnabled = enabled } }
        else { editing.editSnippet(profileID: profileID, snippetID: node.id) { $0.isEnabled = enabled } }
    }
    func destinations(for node: MenuNode) -> [SnippetGroup] {
        profile?.groups.filter { group in
            group.id != currentGroup && (node.kind != .group || profile?.containsGroup(node.id, descendant: group.id) == false)
        } ?? []
    }
    func groupLabel(_ id: UUID) -> String {
        var parts = [groupTitle(id)], cursor = id, seen: Set<UUID> = [id]
        while let parent = profile?.groups.first(where: { $0.children.contains(MenuNode(kind: .group, id: cursor)) }), seen.insert(parent.id).inserted {
            parts.insert(parent.title, at: 0); cursor = parent.id
        }
        return parts.joined(separator: " / ")
    }
    func moveNode(_ node: MenuNode, to group: UUID?) { editing.moveNode(node, in: profileID, to: group) }
    func reorder(_ node: MenuNode, by distance: Int) { editing.reorder(node, in: profileID, by: distance) }
    func removeGroup(_ id: UUID) { editing.removeGroup(id, in: profileID) }
    func addSnippet() { if let id = editing.addSnippet(to: profileID, group: currentGroup) { select(id) } }
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
