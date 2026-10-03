import AppKit
import QuartzCore

final class ApplicationDragView: NSView, NSDraggingSource {
    let applicationURL: URL
    private let applicationIcon: NSImage
    private let iconView = NSImageView(frame: .zero)
    private let nameLabel = NSTextField(labelWithString: "PhrasePerch")
    private let statusLabel = NSTextField(labelWithString: "拖入系统授权列表")
    var onDragEnded: ((Bool) -> Void)?
    init(applicationURL: URL, frame: CGRect) {
        self.applicationURL = applicationURL
        applicationIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        iconView.image = applicationIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = CGRect(x: 8, y: 6, width: 32, height: 32)
        addSubview(iconView)
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.frame = CGRect(x: 48, y: 3, width: frame.width - 58, height: 18)
        addSubview(nameLabel)
        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.frame = CGRect(x: 48, y: 22, width: frame.width - 58, height: 15)
        addSubview(statusLabel)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
        setAccessibilityLabel("将 PhrasePerch 拖入系统授权列表")
        setAccessibilityHelp("拖动此行到系统设置的系统授权列表，然后开启 PhrasePerch")
        toolTip = "拖动此行到系统授权列表，然后开启 PhrasePerch"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        NSCursor.openHand.set()
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        NSCursor.arrow.set()
    }
    func draggingItem() -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: applicationURL as NSURL)
        item.setDraggingFrame(iconView.frame, contents: applicationIcon)
        return item
    }
    override func mouseDragged(with event: NSEvent) {
        beginDraggingSession(with: [draggingItem()], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finishDrag(operation: operation)
    }
    func finishDrag(operation: NSDragOperation) { onDragEnded?(operation.contains(.copy)) }
    func updateStatus(_ text: String, color: NSColor = .secondaryLabelColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
        statusLabel.toolTip = text
    }
}
