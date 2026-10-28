import AppKit
import QuartzCore

class AuthorizationBackdrop: NSVisualEffectView {
    var onBeginMoving: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        onBeginMoving?()
        window?.performDrag(with: event)
    }
}
