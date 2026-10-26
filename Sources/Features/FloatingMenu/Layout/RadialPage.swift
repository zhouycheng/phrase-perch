import AppKit

struct RadialPage {
    let remaining: [RadialNode]
    let slots: [RadialNode?]
    private(set) var layout: RadialLayout
    let consumed: Int
    let titles: [String?]
    let characterLimit: Int
    var hasNext: Bool { consumed < remaining.count }

    func relocated(at point: CGPoint, visible: CGRect, previousAngle: CGFloat? = nil) -> Self? {
        let previous = slots.firstIndex { $0?.action == .previous }
        guard let layout = RadialLayout(anchor: point, visible: visible, count: slots.count,
            pinnedIndex: previous ?? 0, angle: previous == nil ? nil : previousAngle,
            buttonWidths: layout.items.map(\.width)) else { return nil }
        var page = self
        page.layout = layout
        return page
    }

    init?(nodes: [RadialNode], anchor: CGPoint, visible: CGRect, hasPrevious: Bool = false,
        previousAngle: CGFloat? = nil, characterLimit: Int = 10) {
        guard !nodes.isEmpty else { return nil }
        for limit in stride(from: min(30, max(1, characterLimit)), through: 1, by: -1) {
            for consumed in stride(from: min(nodes.count, RadialLayout.maximumItems), through: 1, by: -1) {
                let hasNext = consumed < nodes.count
                var entries = Array(nodes.prefix(consumed))
                if hasNext { entries.append(.next) }
                var slots: [RadialNode?]
                if hasPrevious && hasNext {
                    let needed = consumed + 2
                    let count = needed + needed % 2
                    guard count <= RadialLayout.maximumItems else { continue }
                    slots = Array(repeating: nil, count: count)
                    slots[0] = .next
                    slots[count / 2] = .previous
                    var index = 0
                    for slot in 1..<count where slot != count / 2 && index < consumed {
                        slots[slot] = nodes[index]
                        index += 1
                    }
                } else {
                    if hasPrevious { entries.append(.previous) }
                    slots = entries.map(Optional.some)
                }
                let titles = slots.map { $0?.displayTitle(characterLimit: limit) }
                let widths = zip(slots, titles).map { node, title in
                    floatingButtonWidth(for: title ?? "", accessoryWidth: node?.symbol == nil ? 0 : 20)
                }
                guard slots.count <= RadialLayout.maximumItems,
                    let layout = RadialLayout(anchor: anchor, visible: visible, count: slots.count,
                        pinnedIndex: slots.firstIndex { $0?.action == .previous } ?? 0,
                        angle: hasPrevious ? previousAngle : nil, buttonWidths: widths) else { continue }
                self.remaining = nodes
                self.slots = slots
                self.layout = layout
                self.consumed = consumed
                self.titles = titles
                self.characterLimit = limit
                return
            }
        }
        return nil
    }
}
