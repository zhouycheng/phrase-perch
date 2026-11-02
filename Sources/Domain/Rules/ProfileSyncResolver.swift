import Foundation

extension AppConfiguration {
    func validateSyncReferences() throws {
        var visited = Set<UUID>(), visiting = Set<UUID>()
        func visit(_ profile: AppProfile) throws {
            guard !visiting.contains(profile.id) else { throw InputFailure("同步不能引用自身或形成循环") }
            guard !visited.contains(profile.id) else { return }
            visiting.insert(profile.id)
            for sync in profile.syncs {
                guard let source = profiles.first(where: { $0.id == sync.sourceProfileID }) else {
                    throw InputFailure("同步的来源应用不存在")
                }
                try visit(source)
            }
            visiting.remove(profile.id)
            visited.insert(profile.id)
        }
        for profile in profiles { try visit(profile) }
    }

    func resolvedProfile(_ id: UUID) throws -> AppProfile {
        try validateSyncReferences()
        guard let original = profiles.first(where: { $0.id == id }) else { throw InputFailure("应用已移除") }
        var result = original
        result.buttons = []; result.groups = []; result.syncs = []
        func expand(_ nodes: [MenuNode], in profile: AppProfile, imported: Bool) throws -> [MenuNode] {
            var expanded: [MenuNode] = []
            for node in nodes {
                let runtimeID = imported ? UUID() : node.id
                switch node.kind {
                case .snippet:
                    guard var snippet = profile.buttons.first(where: { $0.id == node.id }) else {
                        throw InputFailure("引用的内容不存在")
                    }
                    snippet.id = runtimeID
                    result.buttons.append(snippet)
                    expanded.append(MenuNode(kind: .snippet, id: runtimeID))
                case .group:
                    guard var group = profile.groups.first(where: { $0.id == node.id }) else {
                        throw InputFailure("引用的分组不存在")
                    }
                    group.id = runtimeID
                    group.children = try expand(group.children, in: profile, imported: imported)
                    result.groups.append(group)
                    expanded.append(MenuNode(kind: .group, id: runtimeID))
                case .sync:
                    guard let sync = profile.syncs.first(where: { $0.id == node.id }),
                        let source = profiles.first(where: { $0.id == sync.sourceProfileID }) else {
                        throw InputFailure("同步的来源应用不存在")
                    }
                    if sync.isEnabled { expanded += try expand(source.rootNodes, in: source, imported: true) }
                }
            }
            return expanded
        }
        // Validate local ownership before walking either group or application references.
        for profile in profiles { try profile.validateHierarchy() }
        result.rootNodes = try expand(original.rootNodes, in: original, imported: false)
        return result
    }
}
