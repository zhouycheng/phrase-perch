import AppKit
import QuartzCore

struct RadialLayout {
    let frame: CGRect
    let anchor: CGPoint  // Animation origin, never clamped.
    let center: CGPoint  // Symmetric ring center, translated as one group at edges.
    let items: [CGRect]
    static let buttonSize = CGSize(width: 88, height: 40)

    init?(anchor: CGPoint, visible: CGRect, count: Int, buttonWidth: CGFloat = Self.buttonSize.width) {
        let buttonSize = CGSize(width: buttonWidth, height: Self.buttonSize.height)
        guard buttonWidth.isFinite, buttonWidth >= Self.buttonSize.width, count > 0, count <= 512, anchor.x.isFinite, anchor.y.isFinite,
            visible.contains(anchor), visible.width >= buttonSize.width + 16, visible.height >= 56
        else { return nil }
        let safe = visible.insetBy(dx: 8, dy: 8)
        // Leave a half-point inside the safety margin so fractional trigonometric
        // coordinates remain contained after translation on negative-coordinate displays.
        let fitting = safe.insetBy(dx: 0.5, dy: 0.5)
        var placed: [CGRect] = []
        var radius: CGFloat = 100
        while radius * 2 + buttonSize.height <= fitting.height {
            let ring = CircularButtonLayout.items(count: count, radius: radius, buttonSize: buttonSize).map {
                CGRect(x: $0.minX, y: -$0.maxY, width: $0.width, height: $0.height)
            }
            let bounds = ring.reduce(CGRect(x: -16, y: -16, width: 32, height: 32)) { $0.union($1) }
            guard bounds.width <= fitting.width, bounds.height <= fitting.height else { return nil }
            if ring.count == count, !ring.enumerated().contains(where: { index, rect in
                ring.dropFirst(index + 1).contains { rect.insetBy(dx: -6, dy: -6).intersects($0) }
            }) {
                placed = ring
                break
            }
            radius += 12
        }
        guard placed.count == count else { return nil }
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
