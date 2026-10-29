import AppKit

final class FloatingMenuLabelView: NSView {
    weak var button: FloatingMenuButton?

    override func draw(_ dirtyRect: NSRect) {
        button?.drawTitle()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}
