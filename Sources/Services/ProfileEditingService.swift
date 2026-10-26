import Foundation

@MainActor
final class ProfileEditingService {
    let repository: ConfigurationRepository
    init(repository: ConfigurationRepository) { self.repository = repository }

    func editProfile(_ id: UUID, _ change: (inout AppProfile) -> Void) {
        guard repository.isReady else { return }
        repository.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: { $0.id == id }) else { return }
            change(&configuration.profiles[index])
        }
    }

    func removeProfile(_ id: UUID) {
        guard repository.isReady else { return }
        repository.update { $0.profiles.removeAll { $0.id == id } }
    }

    func addProfile(_ profile: AppProfile) -> Bool {
        guard repository.isReady,
            !repository.configuration.profiles.contains(where: { $0.application.key == profile.application.key })
        else { return false }
        repository.update { $0.profiles.append(profile) }
        return true
    }

    func editSnippet(profileID: UUID, snippetID: UUID, _ change: (inout Snippet) -> Void) {
        editProfile(profileID) { profile in
            guard let index = profile.buttons.firstIndex(where: { $0.id == snippetID }) else { return }
            change(&profile.buttons[index])
        }
    }

    func addSnippet(to profileID: UUID, group: UUID? = nil) -> UUID? {
        var created: UUID?
        editProfile(profileID) { profile in
            let snippet = Snippet(title: "新文案", text: "在这里填写要插入的内容。")
            var children = profile.children(of: group)
            children.append(MenuNode(kind: .snippet, id: snippet.id))
            profile.buttons.append(snippet)
            profile.setChildren(children, of: group)
            created = snippet.id
        }
        return created
    }

    func addAttachment(from url: URL, to profileID: UUID, group: UUID? = nil) async throws -> UUID {
        guard repository.isReady else { throw InputFailure("配置尚未就绪") }
        let file = try await repository.importAttachment(from: url)
        guard let profile = repository.configuration.profiles.first(where: { $0.id == profileID }),
            group == nil || profile.groups.contains(where: { $0.id == group }) else {
            await repository.abandonAttachment(file.id)
            throw InputFailure("目标应用或分组已移除")
        }
        let snippet = Snippet(title: file.fileName, content: .attachment(file))
        editProfile(profileID) { profile in
            profile.buttons.append(snippet)
            profile.setChildren(profile.children(of: group) + [MenuNode(kind: .snippet, id: snippet.id)], of: group)
        }
        return snippet.id
    }

    func replaceAttachment(_ id: UUID, in profileID: UUID, from url: URL) async throws {
        guard repository.isReady else { throw InputFailure("配置尚未就绪") }
        let file = try await repository.importAttachment(from: url)
        guard repository.configuration.profiles.first(where: { $0.id == profileID })?.buttons
            .contains(where: { $0.id == id && $0.attachment != nil }) == true else {
            await repository.abandonAttachment(file.id)
            throw InputFailure("附件条目已移除")
        }
        editSnippet(profileID: profileID, snippetID: id) { $0.content = .attachment(file) }
    }

    func duplicateSnippet(_ id: UUID, in profileID: UUID) -> UUID? {
        var created: UUID?
        editProfile(profileID) { profile in
            guard var snippet = profile.buttons.first(where: { $0.id == id }) else { return }
            snippet.id = UUID()
            snippet.title += " 副本"
            let parent = profile.groups.first { $0.children.contains(MenuNode(kind: .snippet, id: id)) }?.id
            var children = profile.children(of: parent)
            children.append(MenuNode(kind: .snippet, id: snippet.id))
            profile.buttons.append(snippet)
            profile.setChildren(children, of: parent)
            created = snippet.id
        }
        return created
    }

    func moveSnippet(_ id: UUID, in profileID: UUID, by distance: Int) {
        reorder(MenuNode(kind: .snippet, id: id), in: profileID, by: distance)
    }

    func removeSnippet(_ id: UUID, in profileID: UUID) -> Int? {
        var removed: Int?
        editProfile(profileID) { profile in
            guard let index = profile.buttons.firstIndex(where: { $0.id == id }) else { return }
            let node = MenuNode(kind: .snippet, id: id)
            let parent = profile.groups.first { $0.children.contains(node) }?.id
            let siblings = profile.children(of: parent).filter { $0.kind == .snippet }
            removed = siblings.firstIndex(of: node)
            profile.setChildren(profile.children(of: parent).filter { $0 != node }, of: parent)
            profile.buttons.remove(at: index)
        }
        return removed
    }
    func addGroup(to profileID: UUID, parent: UUID?) {
        editProfile(profileID) { profile in
            let group = SnippetGroup(title: "新分组")
            var children = profile.children(of: parent)
            children.append(MenuNode(kind: .group, id: group.id))
            profile.groups.append(group)
            profile.setChildren(children, of: parent)
        }
    }
    func editGroup(_ id: UUID, in profileID: UUID, _ change: (inout SnippetGroup) -> Void) {
        editProfile(profileID) { profile in
            guard let index = profile.groups.firstIndex(where: { $0.id == id }) else { return }
            change(&profile.groups[index])
        }
    }
    func moveNode(_ node: MenuNode, in profileID: UUID, to destination: UUID?) {
        editProfile(profileID) { profile in
            if let destination {
                guard profile.groups.contains(where: { $0.id == destination }),
                    node.kind != .group || !profile.containsGroup(node.id, descendant: destination) else { return }
            }
            let parent = profile.groups.first { $0.children.contains(node) }?.id
            guard parent != destination, profile.children(of: parent).contains(node) else { return }
            profile.setChildren(profile.children(of: parent).filter { $0 != node }, of: parent)
            profile.setChildren(profile.children(of: destination) + [node], of: destination)
        }
    }
    func reorder(_ node: MenuNode, in profileID: UUID, by distance: Int) {
        editProfile(profileID) { profile in
            let parent = profile.groups.first { $0.children.contains(node) }?.id
            var children = profile.children(of: parent)
            guard let index = children.firstIndex(of: node), children.indices.contains(index + distance) else { return }
            children.swapAt(index, index + distance)
            profile.setChildren(children, of: parent)
        }
    }
    func removeGroup(_ id: UUID, in profileID: UUID) {
        editProfile(profileID) { profile in
            let node = MenuNode(kind: .group, id: id)
            let parent = profile.groups.first { $0.children.contains(node) }?.id
            var children = profile.children(of: parent)
            guard let index = children.firstIndex(of: node) else { return }
            children.replaceSubrange(index...index, with: profile.children(of: id))
            profile.setChildren(children, of: parent)
            profile.groups.removeAll { $0.id == id }
        }
    }

}
