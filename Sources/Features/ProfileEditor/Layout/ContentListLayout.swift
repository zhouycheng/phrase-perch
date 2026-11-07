import Foundation

struct ContentListLayout {
    static let rowHeight: CGFloat = 44
    static let spacing: CGFloat = 8
    static let pageHeaderHeight: CGFloat = 28
    static let avoidanceOutset: CGFloat = 8
    let nodes: [MenuNode]
    let frames: [UUID: CGRect]

    static func avoidance(distance: Int) -> CGFloat {
        (0...4).contains(distance) ? avoidanceOutset * pow(0.7, CGFloat(distance)) : 0
    }

    init(nodes: [MenuNode], markers: [UUID: String], width: CGFloat, excluding: Set<UUID> = []) {
        self.nodes = nodes.filter { !excluding.contains($0.id) }
        var frames: [UUID: CGRect] = [:], y: CGFloat = 0
        for node in self.nodes {
            if markers[node.id] != nil { y += Self.pageHeaderHeight }
            frames[node.id] = CGRect(x: 0, y: y, width: width, height: Self.rowHeight)
            y += Self.rowHeight + Self.spacing
        }
        self.frames = frames
    }
}
