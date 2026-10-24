import Foundation

struct RadialNode: Equatable, Identifiable {
    enum Action: Hashable {
        case text(UUID), group(UUID), previous, next
    }
    let action: Action
    let title: String
    let detail: String
    var id: Action { action }
    var isNavigation: Bool {
        if case .text = action { return false }
        return true
    }
    var textID: UUID? {
        if case .text(let id) = action { return id }
        return nil
    }
    static let previous = RadialNode(action: .previous, title: "← 上一页", detail: "恢复上一张轮盘")
    static let next = RadialNode(action: .next, title: "下一页 →", detail: "展开下一页")
    static func text(_ snippet: Snippet) -> RadialNode {
        RadialNode(action: .text(snippet.id), title: snippet.title, detail: snippet.text)
    }
    static func contents(profile: AppProfile, group: UUID?) -> [RadialNode] {
        let snippets = Dictionary(uniqueKeysWithValues: profile.buttons.map { ($0.id, $0) })
        return profile.enabledNodes(in: group).compactMap { node in
            switch node.kind {
            case .snippet: return snippets[node.id].map(Self.text)
            case .group: return RadialNode(action: .group(node.id), title: "▸ " + profile.title(of: node), detail: "打开分组")
            }
        }
    }
}
