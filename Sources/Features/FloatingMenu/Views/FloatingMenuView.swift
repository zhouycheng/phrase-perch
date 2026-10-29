import AppKit
import QuartzCore

@MainActor
final class FloatingMenuView: NSView {
    private(set) var buttons: [NSButton] = []
    var onSelect: ((RadialNode.Action) -> Void)?
    private var nodes: [RadialNode] = []
    private let content = NSView(frame: .zero)
    var animationLayer: CALayer? { content.layer }
    var allowsClick = false
    func configure(slots: [RadialNode?], layout: RadialLayout, titles: [String?]? = nil, appearance: MenuAppearance = .matte) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        nodes = []
        content.layer?.removeAllAnimations()
        content.layer?.transform = CATransform3DIdentity
        for view in content.subviews { view.removeFromSuperview() }
        content.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        frame = CGRect(origin: .zero, size: layout.frame.size)
        wantsLayer = true
        self.appearance = NSAppearance(named: .darkAqua)
        content.frame = bounds
        content.wantsLayer = true
        if content.superview == nil { addSubview(content) }
        content.layer?.opacity = 1
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: layout.localCenter.x - layout.ringRadius,
            y: layout.localCenter.y - layout.ringRadius, width: layout.ringRadius * 2,
            height: layout.ringRadius * 2), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.withAlphaComponent(0.045).cgColor
        ring.lineWidth = 0.5
        content.layer?.addSublayer(ring)
        buttons = []
        for (slot, entry) in slots.enumerated() {
            guard let node = entry else { continue }
            let button = FloatingMenuButton(frame: layout.itemRect(index: slot))
            button.allowsClick = allowsClick || node.isNavigation
            button.emphasized = node.action == .previous || node.action == .next
            button.target = self
            button.action = button.allowsClick ? #selector(selectNode(_:)) : nil
            button.tag = nodes.count
            button.wantsLayer = true
            button.isBordered = false
            button.focusRingType = .none
            button.title = titles?[slot] ?? node.displayTitle(characterLimit: 10)
            button.symbolName = node.symbol
            button.setAccessibilityLabel(node.title)
            button.toolTip = String(node.detail.prefix(180))
            button.configureAppearance(appearance)
            nodes.append(node)
            buttons.append(button)
            content.addSubview(button)
        }
    }
    @objc private func selectNode(_ sender: NSButton) {
        guard nodes.indices.contains(sender.tag) else { return }
        onSelect?(nodes[sender.tag].action)
    }
    func node(at index: Int) -> RadialNode? { nodes.indices.contains(index) ? nodes[index] : nil }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let index = interactiveIndex(convert(point, from: superview)) else { return nil }
        return buttons[index]
    }
    func interactiveIndex(_ local: CGPoint) -> Int? {
        guard let layer = animationLayer else { return nil }
        let shown = layer.animation(forKey: "radialMotion") == nil ? layer : (layer.presentation() ?? layer)
        let transform = shown.affineTransform()
        guard shown.opacity > 0.05, abs(transform.a * transform.d - transform.b * transform.c) > 0.000001 else { return nil }
        let offset = CGPoint(x: local.x - shown.position.x, y: local.y - shown.position.y)
            .applying(transform.inverted())
        let point = CGPoint(x: offset.x + shown.bounds.minX + shown.anchorPoint.x * shown.bounds.width,
            y: offset.y + shown.bounds.minY + shown.anchorPoint.y * shown.bounds.height)
        return buttons.firstIndex { button in
            guard let buttonLayer = button.layer else { return false }
            let shownButton = buttonLayer.animation(forKey: "nodeHover") == nil
                ? buttonLayer : (buttonLayer.presentation() ?? buttonLayer)
            let offset = CGPoint(x: point.x - shownButton.position.x, y: point.y - shownButton.position.y)
                .applying(shownButton.affineTransform().inverted())
            let local = CGPoint(x: offset.x + shownButton.bounds.minX + shownButton.anchorPoint.x * shownButton.bounds.width,
                y: offset.y + shownButton.bounds.minY + shownButton.anchorPoint.y * shownButton.bounds.height)
            return CGPath(roundedRect: shownButton.bounds, cornerWidth: 12, cornerHeight: 12, transform: nil).contains(local)
        }
    }
    func showSelection(_ index: Int?) {
        for (slot, button) in buttons.enumerated() { (button as? FloatingMenuButton)?.selected = slot == index }
    }
}
