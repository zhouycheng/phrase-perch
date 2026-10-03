import AppKit
import QuartzCore

struct RadialLayout {
    let frame: CGRect
    let anchor: CGPoint  // Animation origin, never clamped.
    let center: CGPoint  // Symmetric ring center, translated as one group at edges.
    let items: [CGRect]
    static let buttonSize = CGSize(width: 88, height: 40)

    init?(anchor: CGPoint, visible: CGRect, count: Int) {
        guard count > 0, count <= 512, anchor.x.isFinite, anchor.y.isFinite,
            visible.contains(anchor), visible.width >= 104, visible.height >= 56
        else { return nil }
        let safe = visible.insetBy(dx: 8, dy: 8)
        // Leave a half-point inside the safety margin so fractional trigonometric
        // coordinates remain contained after translation on negative-coordinate displays.
        let fitting = safe.insetBy(dx: 0.5, dy: 0.5)
        var placed: [CGRect] = []
        var radius: CGFloat = 100
        var ringNumber = 1
        while placed.count < count {
            let slots = min(count - placed.count, ringNumber * 6)
            var ring: [CGRect] = []
            while radius * 2 <= max(safe.width, safe.height) + 100 {
                ring = (0..<slots).map { index in
                    let angle = CGFloat.pi / 2 - CGFloat(index) * 2 * .pi / CGFloat(slots)
                    return CGRect(
                        x: cos(angle) * radius - Self.buttonSize.width / 2,
                        y: sin(angle) * radius - Self.buttonSize.height / 2,
                        width: Self.buttonSize.width, height: Self.buttonSize.height)
                }
                let all = placed + ring
                let collides = all.enumerated().contains { index, rect in
                    all.dropFirst(index + 1).contains { rect.insetBy(dx: -6, dy: -6).intersects($0) }
                }
                if !collides { break }
                radius += 12
            }
            guard !ring.isEmpty,
                !ring.enumerated().contains(where: { index, rect in
                    (placed + Array(ring.dropFirst(index + 1))).contains { rect.insetBy(dx: -6, dy: -6).intersects($0) }
                })
            else { return nil }
            placed += ring
            let bounds = placed.reduce(CGRect(x: -16, y: -16, width: 32, height: 32)) { $0.union($1) }
            guard bounds.width <= fitting.width, bounds.height <= fitting.height else { return nil }
            radius += 72
            ringNumber += 1
        }
        let bounds = placed.reduce(CGRect(x: -16, y: -16, width: 32, height: 32)) { $0.union($1) }
        let center = CGPoint(
            x: max(fitting.minX - bounds.minX, min(anchor.x, fitting.maxX - bounds.maxX)),
            y: max(fitting.minY - bounds.minY, min(anchor.y, fitting.maxY - bounds.maxY)))
        let translated = placed.map { $0.offsetBy(dx: center.x, dy: center.y) }
        guard translated.allSatisfy(safe.contains) else { return nil }
        var windowBounds = CGRect(x: anchor.x, y: anchor.y, width: 1, height: 1)
        for rect in translated { windowBounds = windowBounds.union(rect) }
        frame = windowBounds.insetBy(dx: -8, dy: -8).intersection(visible)
        self.anchor = anchor
        self.center = center
        items = translated
    }
    var localAnchor: CGPoint { CGPoint(x: anchor.x - frame.minX, y: anchor.y - frame.minY) }
    func itemRect(index: Int) -> CGRect { items[index].offsetBy(dx: -frame.minX, dy: -frame.minY) }
    func selectedIndex(at point: CGPoint) -> Int? {
        items.firstIndex { CGPath(roundedRect: $0, cornerWidth: 12, cornerHeight: 12, transform: nil).contains(point) }
    }
}
