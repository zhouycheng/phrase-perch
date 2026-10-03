import AppKit
import QuartzCore

class AuthorizationBackdrop: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
