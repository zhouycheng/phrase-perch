import AppKit
import QuartzCore

struct RadialLayout {
    let frame: CGRect
    let anchor: CGPoint
    let center: CGPoint
    let items: [CGRect]
    let ringRadius: CGFloat
    static let maximumItems = 8
    static let buttonSize = CGSize(width: 88, height: 40)

    static func fittingPage(anchor: CGPoint, visible: CGRect, count: Int, buttonWidth: CGFloat) -> RadialLayout? {
        guard count > 0 else { return nil }
        for capacity in stride(from: min(count, maximumItems), through: 1, by: -1) {
            if let layout = Self(anchor: anchor, visible: visible, count: capacity, buttonWidth: buttonWidth) { return layout }
        }
        return nil
    }

    init?(anchor: CGPoint, visible: CGRect, count: Int, buttonWidth: CGFloat = Self.buttonSize.width,
        pinnedIndex: Int = 0, angle: CGFloat? = nil, buttonWidths: [CGFloat]? = nil) {
        guard buttonWidth.isFinite, buttonWidth >= Self.buttonSize.width, (1...Self.maximumItems).contains(count),
            anchor.x.isFinite, anchor.y.isFinite, visible.contains(anchor) else { return nil }
        let safe = visible.insetBy(dx: 8.5, dy: 8.5)
        let template: [CGRect]
        if let buttonWidths {
            guard buttonWidths.count == count else { return nil }
            let result = CircularButtonLayout.outwardItems(widths: buttonWidths, height: Self.buttonSize.height,
                pinnedIndex: pinnedIndex, angle: angle)
            template = result.items
            ringRadius = result.radius * 0.95
        } else {
            template = CircularButtonLayout.items(count: count,
                buttonSize: CGSize(width: buttonWidth, height: Self.buttonSize.height), pinnedIndex: pinnedIndex, angle: angle)
            ringRadius = template.first.map { hypot($0.midX, $0.midY) * 0.95 } ?? 0
        }
        let ring = template.map {
                CGRect(x: $0.minX, y: -$0.maxY, width: $0.width, height: $0.height)
            }
        guard ring.count == count else { return nil }
        let bounds = ring.reduce(CGRect(x: -24, y: -24, width: 48, height: 48)) { $0.union($1) }
        guard bounds.width <= safe.width, bounds.height <= safe.height else { return nil }
        let center = CGPoint(
            x: max(safe.minX - bounds.minX, min(anchor.x, safe.maxX - bounds.maxX)),
            y: max(safe.minY - bounds.minY, min(anchor.y, safe.maxY - bounds.maxY)))
        let translated = ring.map { $0.offsetBy(dx: center.x, dy: center.y) }
        guard translated.allSatisfy(visible.insetBy(dx: 8, dy: 8).contains) else { return nil }
        self.anchor = anchor
        self.center = center
        items = translated
        let radius = ring.map { hypot(max(abs($0.minX), abs($0.maxX)), max(abs($0.minY), abs($0.maxY))) }
            .max()! * FloatingMenuAnimationConfiguration.peakScale
        let envelope = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        frame = envelope.offsetBy(dx: center.x, dy: center.y)
            .union(envelope.offsetBy(dx: anchor.x, dy: anchor.y))
            .insetBy(dx: -8, dy: -8).intersection(visible)
    }
    var localAnchor: CGPoint { CGPoint(x: anchor.x - frame.minX, y: anchor.y - frame.minY) }
    var localCenter: CGPoint { CGPoint(x: center.x - frame.minX, y: center.y - frame.minY) }
    func itemRect(index: Int) -> CGRect { items[index].offsetBy(dx: -frame.minX, dy: -frame.minY) }
    func selectedIndex(at point: CGPoint) -> Int? {
        items.firstIndex { CGPath(roundedRect: $0, cornerWidth: 12, cornerHeight: 12, transform: nil).contains(point) }
    }
}
