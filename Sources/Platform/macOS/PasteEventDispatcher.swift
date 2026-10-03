import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

enum PasteEventDispatcher {
    static func makeEvents() -> (CGEvent, CGEvent)? {
        guard let source = CGEventSource(stateID: .privateState),
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: clipboardPasteEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: clipboardPasteEventTag)
        return (down, up)
    }
    static func dispatch() -> Bool {
        guard let (down, up) = makeEvents() else { return false }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}
