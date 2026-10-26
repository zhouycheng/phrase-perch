import AppKit
import QuartzCore

final class FloatingMenuButton: NonactivatingButton {
    var selected = false { didSet { needsDisplay = true } }
    var emphasized = false { didSet { needsDisplay = true } }
    var allowsClick = false
    var symbolName: String?
    override func mouseDown(with event: NSEvent) {
        if allowsClick { super.mouseDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool {
        guard allowsClick else { return false }
        performClick(nil)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        let fill = selected ? NSColor.controlAccentColor.blended(withFraction: 0.18, of: .white) ?? .controlAccentColor
            : emphasized ? NSColor.controlAccentColor : NSColor(calibratedWhite: 0.09, alpha: 0.97)
        fill.setFill()
        shape.fill()
        NSColor.white.withAlphaComponent(selected ? 0.6 : 0.18).setStroke()
        shape.lineWidth = selected ? 1.5 : 0.8
        shape.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: snippetTitleFontSize, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let iconWidth: CGFloat = symbolName == nil ? 0 : 20
        let left = max(10, (bounds.width - size.width - iconWidth) / 2)
        if let symbolName, let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.white])) {
            image.draw(in: CGRect(x: left, y: (bounds.height - 13) / 2, width: 13, height: 13))
        }
        (title as NSString).draw(
            in: CGRect(x: left + iconWidth, y: (bounds.height - size.height) / 2,
                width: min(size.width, bounds.width - left - iconWidth - 10), height: size.height),
            withAttributes: attributes)
    }
}
