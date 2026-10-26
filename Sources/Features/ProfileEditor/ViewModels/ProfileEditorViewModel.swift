import CoreGraphics
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
    private(set) var selectedNodeIDs = Set<UUID>()
    private(set) var batchDeletionIDs: Set<UUID>?
    private(set) var batchDeletionMessage = ""
    private var batchDeletionMembers = Set<UUID>()
    private(set) var batchIssue: String?
    private(set) var marqueeRect: CGRect?
    private(set) var draggingNodeIDs = Set<UUID>()
    private(set) var insertionBeforeID: UUID?
    private var gestureSelection = Set<UUID>()
    private var gestureOrder: [UUID] = []
    private var marqueeStart: CGPoint?
    var showSaveIssue = false
    private(set) var groupPath: [UUID] = []
    var currentGroup: UUID? { groupPath.last }
    var nodes: [MenuNode] { profile?.children(of: currentGroup) ?? [] }
    var onOpenConfiguration: (() -> Void)?
    private let chooseAttachments: (Bool) -> [URL]
    private(set) var isImportingAttachment = false
    private(set) var attachmentMessage: String?
    private(set) var attachmentAvailable: Bool?

    init(
        profileID: UUID, repository: ConfigurationRepository, editing: ProfileEditingService,
        session: SnippetEditorSession = SnippetEditorSession(), chooseAttachments: @escaping (Bool) -> [URL] = { _ in [] }
    ) {
        self.profileID = profileID
        self.repository = repository
        self.editing = editing
        self.session = session
        self.chooseAttachments = chooseAttachments
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
    var textIssue: String? { selectedSnippet.flatMap { $0.attachment == nil ? SnippetValidator.textIssue($0.text) : nil } }
    func isAttachment(_ id: UUID) -> Bool { profile?.buttons.first { $0.id == id }?.attachment != nil }
    func title(_ id: UUID) -> String { profile?.buttons.first { $0.id == id }?.title ?? "" }
    func text(_ id: UUID) -> String { profile?.buttons.first { $0.id == id }?.text ?? "" }
    func setTitle(_ value: String, id: UUID) {
        editing.editSnippet(profileID: profileID, snippetID: id) { $0.title = value }
    }
    func setText(_ value: String, id: UUID) {
        editing.editSnippet(profileID: profileID, snippetID: id) { if $0.attachment == nil { $0.text = value } }
    }
    func select(_ id: UUID) {
        guard ids.contains(id) else { return }
        session.select(id, in: ids)
        showSaveIssue = false
        attachmentMessage = nil
        attachmentAvailable = nil
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
        selectedNodeIDs.formIntersection(nodes.map(\.id))
        if !gestureOrder.isEmpty && gestureOrder != nodes.map(\.id) { cancelListGesture() }
        if saveStatus != "保存失败" { showSaveIssue = false }
    }
    func openGroup(_ id: UUID?) {
        clearBatchSelection()
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
    func addAttachments() {
        guard !isImportingAttachment else { return }
        let urls = chooseAttachments(true), group = currentGroup
        guard !urls.isEmpty else { return }
        isImportingAttachment = true
        attachmentMessage = nil
        Task {
            var failures: [String] = []
            for url in urls {
                do { select(try await editing.addAttachment(from: url, to: profileID, group: group)) }
                catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
            attachmentMessage = failures.isEmpty ? nil : failures.joined(separator: "；")
            isImportingAttachment = false
        }
    }
    func replaceAttachment() {
        guard !isImportingAttachment, let id = selectedSnippet?.id, let url = chooseAttachments(false).first else { return }
        isImportingAttachment = true
        attachmentMessage = nil
        Task {
            do { try await editing.replaceAttachment(id, in: profileID, from: url) }
            catch { attachmentMessage = error.localizedDescription }
            isImportingAttachment = false
        }
    }
    func checkAttachment(_ file: AttachmentReference) async {
        let available = (try? await repository.attachmentURL(file)) != nil
        guard selectedSnippet?.attachment == file else { return }
        attachmentAvailable = available
    }
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
    var batchProfiles: [AppProfile] { repository.configuration.profiles }
    var isBatchSelecting: Bool { !selectedNodeIDs.isEmpty }
    var isListGestureActive: Bool { marqueeRect != nil || !draggingNodeIDs.isEmpty }

    func toggleNodeSelection(_ id: UUID) {
        guard nodes.contains(where: { $0.id == id }) else { return }
        if !selectedNodeIDs.insert(id).inserted { selectedNodeIDs.remove(id) }
        batchIssue = nil
    }
    func activateNode(_ node: MenuNode) {
        if isBatchSelecting { toggleNodeSelection(node.id) }
        else if node.kind == .group { openGroup(node.id) }
        else { select(node.id) }
    }
    func clearBatchSelection() {
        cancelListGesture()
        selectedNodeIDs = []
        batchDeletionIDs = nil
        batchIssue = nil
    }
    func canTransferSelection(to destination: AppProfile, group: UUID?, copying: Bool) -> Bool {
        guard isBatchSelecting else { return false }
        guard !copying, destination.id == profileID else { return true }
        if group == currentGroup { return false }
        return group == nil || !nodes.contains { node in
            selectedNodeIDs.contains(node.id) && node.kind == .group
                && profile?.containsGroup(node.id, descendant: group!) == true
        }
    }
    func transferSelection(to destination: UUID, group: UUID?, copying: Bool) {
        do {
            try editing.transferNodes(selectedNodeIDs, from: profileID, group: currentGroup,
                to: destination, group: group, copying: copying)
            batchIssue = nil
            if !copying { clearBatchSelection() }
        } catch { batchIssue = error.localizedDescription }
    }
    func requestBatchDeletion() {
        do {
            let counts = try editing.deletionCounts(selectedNodeIDs, in: profileID, group: currentGroup)
            batchDeletionIDs = selectedNodeIDs
            batchDeletionMembers = counts.ids
            batchDeletionMessage = "将删除 \(counts.groups) 个分组和 \(counts.contents) 条内容，包含所选分组内的全部内容。"
        } catch { batchIssue = error.localizedDescription }
    }
    func cancelBatchDeletion() { batchDeletionIDs = nil }
    func confirmBatchDeletion() {
        guard let selection = batchDeletionIDs else { return }
        batchDeletionIDs = nil
        do {
            guard try editing.deletionCounts(selection, in: profileID, group: currentGroup).ids == batchDeletionMembers else {
                throw InputFailure("所选分组的内容已变化，请重新确认删除")
            }
            try editing.deleteNodes(selection, in: profileID, group: currentGroup)
            clearBatchSelection()
        } catch { batchIssue = error.localizedDescription }
    }
    func beginMarquee(at point: CGPoint, additive: Bool) {
        guard !isListGestureActive else { return }
        gestureSelection = selectedNodeIDs
        gestureOrder = nodes.map(\.id)
        marqueeStart = point
        marqueeRect = CGRect(origin: point, size: .zero)
        if !additive { selectedNodeIDs = [] }
    }
    func updateMarquee(to point: CGPoint, frames: [UUID: CGRect], additive: Bool) {
        guard let start = marqueeStart else { return }
        let rectangle = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
            width: abs(point.x - start.x), height: abs(point.y - start.y))
        marqueeRect = rectangle
        let hits = Set(nodes.compactMap { node in frames[node.id]?.intersects(rectangle) == true ? node.id : nil })
        selectedNodeIDs = hits.union(additive ? gestureSelection : [])
    }
    func beginReordering(_ id: UUID) {
        guard !isListGestureActive, nodes.contains(where: { $0.id == id }) else { return }
        gestureSelection = selectedNodeIDs
        gestureOrder = nodes.map(\.id)
        if !selectedNodeIDs.contains(id) { selectedNodeIDs = [id] }
        draggingNodeIDs = selectedNodeIDs
        insertionBeforeID = id
    }
    func updateInsertion(at point: CGPoint, frames: [UUID: CGRect]) {
        guard !draggingNodeIDs.isEmpty else { return }
        insertionBeforeID = nodes.first { node in
            !draggingNodeIDs.contains(node.id) && frames[node.id].map { point.y < $0.midY } == true
        }?.id
    }
    func finishListGesture(inside: Bool) {
        guard inside else { cancelListGesture(); return }
        let dragged = draggingNodeIDs, next = insertionBeforeID
        resetListGesture()
        guard !dragged.isEmpty else { return }
        do { try editing.reorderNodes(dragged, in: profileID, group: currentGroup, before: next) }
        catch { batchIssue = error.localizedDescription }
    }
    func cancelListGesture() {
        if isListGestureActive { selectedNodeIDs = gestureSelection.intersection(nodes.map(\.id)) }
        resetListGesture()
    }
    private func resetListGesture() {
        marqueeRect = nil
        marqueeStart = nil
        draggingNodeIDs = []
        insertionBeforeID = nil
        gestureOrder = []
        gestureSelection = []
    }
    func retrySave() { Task { _ = await repository.flush() } }
    func openConfiguration() {
        showSaveIssue = false
        onOpenConfiguration?()
    }
}
