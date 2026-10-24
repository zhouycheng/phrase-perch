import AppKit
import QuartzCore

@MainActor
final class FloatingMenuView: NSView {
    private(set) var buttons: [NSButton] = []
    var onSelect: ((RadialNode.Action) -> Void)?
    private var nodes: [RadialNode] = []
    var allowsClick = false
    func configure(slots: [RadialNode?], layout: RadialLayout) {
        nodes = []
        for view in subviews { view.removeFromSuperview() }
        frame = CGRect(origin: .zero, size: layout.frame.size)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
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
            button.title = floatingButtonTitle(node.title)
            button.setAccessibilityLabel(node.title)
            button.toolTip = String(node.detail.prefix(180))
            nodes.append(node)
            buttons.append(button)
            addSubview(button)
        }
    }
    var animatedButtons: [NSButton] { buttons }
    @objc private func selectNode(_ sender: NSButton) {
        guard nodes.indices.contains(sender.tag) else { return }
        onSelect?(nodes[sender.tag].action)
    }
    func node(at index: Int) -> RadialNode? { nodes.indices.contains(index) ? nodes[index] : nil }
    func interactiveIndex(_ local: CGPoint) -> Int? {
        buttons.firstIndex { button in
            guard let layer = button.layer else { return false }
            let shown = layer.presentation() ?? layer
            guard shown.opacity > 0.05 else { return false }
            let rect = shown.frame
            let scale = min(rect.width / RadialLayout.buttonSize.width, rect.height / RadialLayout.buttonSize.height)
            return CGPath(roundedRect: rect, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil)
                .contains(local)
        }
    }
    func showSelection(_ index: Int?) {
        for (slot, button) in buttons.enumerated() { (button as? FloatingMenuButton)?.selected = slot == index }
    }
}
