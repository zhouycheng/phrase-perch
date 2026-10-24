import Foundation

struct MenuNode: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case snippet, group }
    var kind: Kind
    var id: UUID
}

extension AppProfile {
    func children(of group: UUID?) -> [MenuNode] {
        guard let group else { return rootNodes }
        return groups.first { $0.id == group }?.children ?? []
    }
    mutating func setChildren(_ items: [MenuNode], of group: UUID?) {
        if let group, let index = groups.firstIndex(where: { $0.id == group }) { groups[index].children = items }
        else if group == nil { rootNodes = items }
    }
    func title(of node: MenuNode) -> String {
        node.kind == .snippet ? buttons.first { $0.id == node.id }?.title ?? "" : groups.first { $0.id == node.id }?.title ?? ""
    }
    func enabledNodes(in group: UUID? = nil) -> [MenuNode] {
        var available = Set(buttons.filter(\.isEnabled).map(\.id))
        var changed = true
        while changed {
            changed = false
            for group in groups where group.isEnabled && !available.contains(group.id) {
                if group.children.contains(where: { available.contains($0.id) }) {
                    available.insert(group.id)
                    changed = true
                }
            }
        }
        return children(of: group).filter { available.contains($0.id) }
    }
    func containsGroup(_ ancestor: UUID, descendant: UUID) -> Bool {
        var pending = [ancestor]
        var seen = Set<UUID>()
        while let id = pending.popLast() {
            if id == descendant { return true }
            guard seen.insert(id).inserted else { continue }
            pending += children(of: id).filter { $0.kind == .group }.map(\.id)
        }
        return false
    }
    func validateHierarchy() throws {
        let snippets = Set(buttons.map(\.id)), groupIDs = Set(groups.map(\.id))
        var visited = Set<UUID>(), pending = rootNodes
        while let node = pending.popLast() {
            guard visited.insert(node.id).inserted else { throw InputFailure("分组存在重复引用或循环归属") }
            switch node.kind {
            case .snippet:
                guard snippets.contains(node.id) else { throw InputFailure("分组引用的文案不存在") }
            case .group:
                guard groupIDs.contains(node.id) else { throw InputFailure("分组引用的子分组不存在") }
                pending += children(of: node.id)
            }
        }
        guard visited == snippets.union(groupIDs) else { throw InputFailure("存在未归属的文案或分组") }
    }
}
