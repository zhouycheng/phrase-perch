import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

struct CapturedInputTarget: Equatable, Sendable {
    let id: UUID
    let caretBounds: CGRect?  // AX screen coordinates; the retained element stays inside AccessibilityInputWorker.
    let editorBounds: CGRect?

    init(id: UUID, caretBounds: CGRect?, editorBounds: CGRect? = nil) {
        self.id = id
        self.caretBounds = caretBounds
        self.editorBounds = editorBounds
    }
}
