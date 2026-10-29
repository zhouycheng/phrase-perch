import AppKit
import QuartzCore

final class FloatingMenuButton: NonactivatingButton {
    private var glassBackground: NSView?
    var selected = false {
        didSet {
            guard selected != oldValue else { return }
            needsDisplay = true
            updateGlassTint()
            animateHover()
        }
    }
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
    private func animateHover() {
        guard let layer else { return }
        let scale: CGFloat = selected && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? FloatingMenuAnimationConfiguration.hoverScale : 1
        let current = layer.presentation()?.transform ?? layer.transform
        let pivot = CGPoint(x: bounds.midX - layer.anchorPoint.x * bounds.width,
            y: bounds.midY - layer.anchorPoint.y * bounds.height)
        var target = CATransform3DMakeScale(scale, scale, 1)
        target.m41 = pivot.x * (1 - scale)
        target.m42 = pivot.y * (1 - scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: current)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = selected ? 0.12 : 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "nodeHover")
        CATransaction.commit()
    }

    func configureAppearance(_ appearance: MenuAppearance) {
        glassBackground?.removeFromSuperview()
        glassBackground = nil
        guard appearance != .matte, #available(macOS 26, *) else { needsDisplay = true; return }
        let glass = NSGlassEffectView(frame: bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = 12
        glass.style = appearance == .clearGlass ? .clear : .regular
        let label = FloatingMenuLabelView(frame: bounds)
        label.button = self
        label.autoresizingMask = [.width, .height]
        glass.contentView = label
        glass.setAccessibilityElement(false)
        addSubview(glass)
        glassBackground = glass
        updateGlassTint()
        needsDisplay = true
    }

    private func updateGlassTint() {
        guard #available(macOS 26, *), let glass = glassBackground as? NSGlassEffectView else { return }
        glass.tintColor = selected || emphasized ? NSColor.controlAccentColor : nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func draw(_ dirtyRect: NSRect) {
        guard glassBackground == nil else { return }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        let fill = selected ? NSColor.controlAccentColor.blended(withFraction: 0.18, of: .white) ?? .controlAccentColor
            : emphasized ? NSColor.controlAccentColor : NSColor(calibratedWhite: 0.115, alpha: 0.98)
        fill.setFill()
        shape.fill()
        drawTitle()
    }

    func drawTitle() {
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
