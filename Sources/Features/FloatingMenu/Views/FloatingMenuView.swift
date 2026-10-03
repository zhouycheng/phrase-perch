import AppKit
import QuartzCore

@MainActor
final class FloatingMenuView: NSView {
    private(set) var buttons: [NSButton] = []
    func configure(snippets: [Snippet], layout: RadialLayout) {
        for view in subviews { view.removeFromSuperview() }
        frame = CGRect(origin: .zero, size: layout.frame.size)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        buttons = []
        for index in snippets.indices {
            let rect = layout.itemRect(index: index)
            let button = FloatingMenuButton(frame: rect)
            button.wantsLayer = true
            button.isBordered = false
            button.focusRingType = .none
            button.title = floatingButtonTitle(snippets[index].title)
            button.setAccessibilityLabel(snippets[index].title)
            button.toolTip = String(snippets[index].text.prefix(180))
            buttons.append(button)
            addSubview(button)
        }
        // The empty center is the cancellation area; it neither receives focus nor blocks the editor.
    }
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
