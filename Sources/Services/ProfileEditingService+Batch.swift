import Foundation

extension ProfileEditingService {
    func transferNodes(_ ids: Set<UUID>, from profileID: UUID, group: UUID?,
        to destinationID: UUID, group destinationGroup: UUID?, copying: Bool) throws {
        let selection = try selectedNodes(ids, in: profileID, group: group)
        var configuration = repository.configuration
        guard let sourceIndex = configuration.profiles.firstIndex(where: { $0.id == profileID }),
            let destinationIndex = configuration.profiles.firstIndex(where: { $0.id == destinationID }) else {
            throw InputFailure("目标应用已移除")
        }
        var source = selection.profile
        var destination = configuration.profiles[destinationIndex]
        try destination.validateHierarchy()
        guard destinationGroup == nil || destination.groups.contains(where: { $0.id == destinationGroup }) else {
            throw InputFailure("目标分组已移除")
        }
        if !copying && profileID == destinationID {
            guard group != destinationGroup else { throw InputFailure("所选内容已在此位置") }
            if let destinationGroup, selection.roots.contains(where: {
                $0.kind == .group && source.containsGroup($0.id, descendant: destinationGroup)
            }) { throw InputFailure("不能将分组移动到自身或子分组") }
        }
        var roots = selection.roots
        let memberIDs = Set(selection.members.map(\.id))
        var snippets = source.buttons.filter { memberIDs.contains($0.id) }
        var groups = source.groups.filter { memberIDs.contains($0.id) }
        if copying {
            let replacements = Dictionary(uniqueKeysWithValues: memberIDs.map { ($0, UUID()) })
            func remap(_ nodes: [MenuNode]) -> [MenuNode] {
                nodes.map { MenuNode(kind: $0.kind, id: replacements[$0.id]!) }
            }
            roots = remap(roots)
            snippets = snippets.map { item in
                var copy = item; copy.id = replacements[item.id]!; return copy
            }
            groups = groups.map { item in
                var copy = item; copy.id = replacements[item.id]!; copy.children = remap(item.children); return copy
            }
        } else {
            source.setChildren(source.children(of: group).filter { !ids.contains($0.id) }, of: group)
            if sourceIndex == destinationIndex { destination = source }
            else {
                source.buttons.removeAll { memberIDs.contains($0.id) }
                source.groups.removeAll { memberIDs.contains($0.id) }
            }
            if sourceIndex != destinationIndex { try source.validateHierarchy() }
            configuration.profiles[sourceIndex] = source
        }
        if copying || sourceIndex != destinationIndex {
            destination.buttons += snippets
            destination.groups += groups
        }
        destination.setChildren(destination.children(of: destinationGroup) + roots, of: destinationGroup)
        try destination.validateHierarchy()
        configuration.profiles[destinationIndex] = destination
        repository.update { $0 = configuration }
    }

    func deleteNodes(_ ids: Set<UUID>, in profileID: UUID, group: UUID?) throws {
        let selection = try selectedNodes(ids, in: profileID, group: group)
        let memberIDs = Set(selection.members.map(\.id))
        var profile = selection.profile
        profile.setChildren(profile.children(of: group).filter { !ids.contains($0.id) }, of: group)
        profile.buttons.removeAll { memberIDs.contains($0.id) }
        profile.groups.removeAll { memberIDs.contains($0.id) }
        try profile.validateHierarchy()
        editProfile(profileID) { $0 = profile }
    }

    func deletionCounts(_ ids: Set<UUID>, in profileID: UUID, group: UUID?) throws -> (groups: Int, contents: Int, ids: Set<UUID>) {
        let members = try selectedNodes(ids, in: profileID, group: group).members
        return (members.filter { $0.kind == .group }.count, members.filter { $0.kind == .snippet }.count, Set(members.map(\.id)))
    }

    func reorderNodes(_ ids: Set<UUID>, in profileID: UUID, group: UUID?, before nextID: UUID?) throws {
        let selection = try selectedNodes(ids, in: profileID, group: group)
        if let nextID, ids.contains(nextID) { return }
        var profile = selection.profile
        var remaining = profile.children(of: group).filter { !ids.contains($0.id) }
        let index: Int
        if let nextID {
            guard let found = remaining.firstIndex(where: { $0.id == nextID }) else {
                throw InputFailure("排序位置已变化，请重试")
            }
            index = found
        } else { index = remaining.count }
        remaining.insert(contentsOf: selection.roots, at: index)
        profile.setChildren(remaining, of: group)
        editProfile(profileID) { $0 = profile }
    }

    private func selectedNodes(_ ids: Set<UUID>, in profileID: UUID, group: UUID?) throws
        -> (profile: AppProfile, roots: [MenuNode], members: [MenuNode]) {
        guard repository.isReady else { throw InputFailure("配置尚未就绪") }
        guard let profile = repository.configuration.profiles.first(where: { $0.id == profileID }),
            group == nil || profile.groups.contains(where: { $0.id == group }) else {
            throw InputFailure("来源应用或分组已移除")
        }
        try profile.validateHierarchy()
        let roots = profile.children(of: group).filter { ids.contains($0.id) }
        guard !ids.isEmpty, Set(roots.map(\.id)) == ids else { throw InputFailure("所选内容已变化，请重新选择") }
        var members: [MenuNode] = [], pending = roots
        while let node = pending.popLast() {
            members.append(node)
            if node.kind == .group { pending += profile.children(of: node.id) }
        }
        return (profile, roots, members)
    }
}
