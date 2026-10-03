import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

struct CapturedInputTarget: Equatable, Sendable {
    let id: UUID
    let caretBounds: CGRect?  // AX screen coordinates; the retained element stays inside AccessibilityInputWorker.
}
