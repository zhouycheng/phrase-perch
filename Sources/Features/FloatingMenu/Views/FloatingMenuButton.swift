import AppKit
import QuartzCore

final class FloatingMenuButton: NonactivatingButton {
    var selected = false { didSet { needsDisplay = true } }
    override func mouseDown(with event: NSEvent) {}  // Release of the trigger commits, never a click.
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        (selected ? NSColor.controlAccentColor : NSColor(calibratedWhite: 0.09, alpha: 0.97)).setFill()
        shape.fill()
        NSColor.white.withAlphaComponent(selected ? 0.6 : 0.18).setStroke()
        shape.lineWidth = selected ? 1.5 : 0.8
        shape.stroke()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes)
    }
}
