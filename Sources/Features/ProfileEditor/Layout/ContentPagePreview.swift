import AppKit

struct ContentPagePreview: Equatable {
    var markers: [UUID: String] = [:]
    var ranges: [UUID: ClosedRange<Int>] = [:]
    var issue: String?

    init() {}

    init(configuration: AppConfiguration, profileID: UUID, groupPath: [UUID], visible: CGRect) {
        do {
            let resolved = try configuration.resolveProfile(profileID)
            let profile = resolved.profile
            let limit = configuration.preferences.menuTitleCharacterLimit
            let root = RadialNode.contents(profile: profile, group: nil)
            guard !root.isEmpty else { return }
            var page = try makePage(nodes: root, at: CGPoint(x: visible.midX, y: visible.midY),
                visible: visible, characterLimit: limit)
            for group in groupPath {
                while !page.slots.contains(where: { $0?.action == .group(group) }) {
                    guard page.hasNext else { return }
                    page = try nextPage(page, visible: visible, characterLimit: limit)
                }
                let nodes = RadialNode.contents(profile: profile, group: group)
                guard !nodes.isEmpty else { return }
                page = try navigate(from: page, action: .group(group), nodes: nodes,
                    visible: visible, characterLimit: limit)
            }
            var number = 1
            while true {
                for node in page.remaining.prefix(page.consumed) {
                    let runtimeID: UUID
                    switch node.action {
                    case .content(let id), .group(let id): runtimeID = id
                    default: continue
                    }
                    guard let localID = resolved.localNodeIDs[runtimeID] else { continue }
                    ranges[localID] = (ranges[localID]?.lowerBound ?? number)...number
                }
                guard page.hasNext else { break }
                page = try nextPage(page, visible: visible, characterLimit: limit)
                number += 1
            }
            var displayedPage = 1, coveredThrough = 1
            let localNodes = configuration.profiles.first { $0.id == profileID }?.children(of: groupPath.last) ?? []
            for node in localNodes {
                guard let range = ranges[node.id] else { continue }
                if range.lowerBound > displayedPage {
                    markers[node.id] = "第 \(range.lowerBound) 页" + (range.lowerBound <= coveredThrough ? "（续）" : "")
                    displayedPage = range.lowerBound
                }
                coveredThrough = max(coveredThrough, range.upperBound)
            }
        } catch {
            markers = [:]; ranges = [:]
            issue = error.localizedDescription
        }
    }

    func rangeLabel(for id: UUID) -> String? {
        guard let range = ranges[id] else { return nil }
        return range.lowerBound == range.upperBound ? "第 \(range.lowerBound) 页"
            : "第 \(range.lowerBound)–\(range.upperBound) 页"
    }

    private func makePage(nodes: [RadialNode], at point: CGPoint, visible: CGRect,
        hasPrevious: Bool = false, previousAngle: CGFloat? = nil, characterLimit: Int) throws -> RadialPage {
        guard let page = RadialPage(nodes: nodes, anchor: point, visible: visible,
            hasPrevious: hasPrevious, previousAngle: previousAngle, characterLimit: characterLimit) else {
            throw InputFailure("当前屏幕空间不足，无法预览分页")
        }
        return page
    }

    private func nextPage(_ page: RadialPage, visible: CGRect, characterLimit: Int) throws -> RadialPage {
        try navigate(from: page, action: .next, nodes: Array(page.remaining.dropFirst(page.consumed)),
            visible: visible, characterLimit: characterLimit)
    }

    private func navigate(from page: RadialPage, action: RadialNode.Action, nodes: [RadialNode],
        visible: CGRect, characterLimit: Int) throws -> RadialPage {
        guard let index = page.slots.firstIndex(where: { $0?.action == action }) else {
            throw InputFailure("内容已变化，无法预览分页")
        }
        let item = page.layout.items[index]
        let point = CGPoint(x: item.midX, y: item.midY)
        return try makePage(nodes: nodes, at: point, visible: visible, hasPrevious: true,
            previousAngle: atan2(page.layout.center.x - point.x, page.layout.center.y - point.y), characterLimit: characterLimit)
    }
}
