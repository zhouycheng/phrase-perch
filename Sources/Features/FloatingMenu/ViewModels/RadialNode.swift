import Foundation

struct RadialNode: Equatable, Identifiable {
    enum Action: Hashable {
        case content(UUID), group(UUID), previous, next
    }
    let action: Action
    let title: String
    let detail: String
    var symbol: String?
    var id: Action { action }
    var isNavigation: Bool {
        if case .content = action { return false }
        return true
    }
    var contentID: UUID? {
        if case .content(let id) = action { return id }
        return nil
    }
    static let previous = RadialNode(action: .previous, title: "← 上一页", detail: "恢复上一张轮盘")
    static let next = RadialNode(action: .next, title: "下一页 →", detail: "展开下一页")
    func displayTitle(characterLimit: Int) -> String {
        if action == .previous || action == .next { return title }
        return floatingButtonTitle(title, characterLimit: characterLimit)
    }
    static func content(_ snippet: Snippet) -> RadialNode {
        RadialNode(action: .content(snippet.id), title: snippet.title,
            detail: snippet.attachment?.fileName ?? snippet.text, symbol: snippet.attachment == nil ? nil : "paperclip")
    }
    static func contents(profile: AppProfile, group: UUID?) -> [RadialNode] {
        let snippets = Dictionary(uniqueKeysWithValues: profile.buttons.map { ($0.id, $0) })
        return profile.enabledNodes(in: group).compactMap { node in
            switch node.kind {
            case .snippet: return snippets[node.id].map(Self.content)
            case .group: return RadialNode(action: .group(node.id), title: profile.title(of: node), detail: "打开分组", symbol: "chevron.right")
            }
        }
    }
}
