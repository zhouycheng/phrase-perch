import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

struct CapturedInputTarget: Equatable, Sendable {
    let id: UUID
    let caretBounds: CGRect?  // AX screen coordinates; the retained element stays inside AccessibilityInputWorker.
    let editorBounds: CGRect?
    enum FocusKind: Sendable { case editable, nonInput, unknown }
    var focusKind = FocusKind.editable
    var canDirectWrite = false
    var canPaste = true
    var detail = ""
    var usedCachedCaret = false
    var screenID: UInt32?
    var anchorSource = ""

    init(id: UUID, caretBounds: CGRect?, editorBounds: CGRect? = nil) {
        self.id = id
        self.caretBounds = caretBounds
        self.editorBounds = editorBounds
    }
}
