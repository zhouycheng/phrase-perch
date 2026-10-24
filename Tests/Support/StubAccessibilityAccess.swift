import AppKit
import ApplicationServices
@testable import PhrasePerch

final class StubAccessibilityAccess: AccessibilityAccess, @unchecked Sendable {
    let editor = AXUIElementCreateApplication(4242)
    let replacement = AXUIElementCreateApplication(4243)
    var trusted = true
    var secureInput = false
    var observesChanges = false
    var role = kAXTextAreaRole as String
    var subrole: String?
    var enabled: Bool? = true
    var readOnly = false
    var hasRange = true
    var writable = false
    var editableAncestor = true
    var identifier = "com.apple.Safari"
    var focusError = AXError.success
    var failuresRemaining = 0
    var focusReads = 0
    var changeFocusAfterFirstRead = false
    var text = "正文"
    func attribute(_ element: AXUIElement, _ name: CFString) -> (AXError, CFTypeRef?) {
        switch name as String {
        case kAXFocusedUIElementAttribute as String:
            focusReads += 1
            if failuresRemaining > 0 { failuresRemaining -= 1; return (.cannotComplete, nil) }
            if focusError != .success { return (focusError, nil) }
            return (.success, changeFocusAfterFirstRead && focusReads > 1 ? replacement : editor)
        case kAXRoleAttribute as String: return (.success, role as CFString)
        case kAXSubroleAttribute as String: return (.success, subrole as CFString?)
        case kAXEnabledAttribute as String: return (.success, enabled.map { $0 ? kCFBooleanTrue! : kCFBooleanFalse! })
        case "AXReadOnly": return (.success, readOnly ? kCFBooleanTrue : kCFBooleanFalse)
        case "AXEditableAncestor": return editableAncestor ? (.success, editor) : (.attributeUnsupported, nil)
        case kAXSelectedTextRangeAttribute as String:
            guard hasRange else { return (.attributeUnsupported, nil) }
            var range = CFRange(location: 0, length: 0)
            return (.success, AXValueCreate(.cfRange, &range))
        case kAXValueAttribute as String: return (.success, text as CFString)
        case kAXPositionAttribute as String:
            var point = CGPoint(x: 100, y: 100)
            return (.success, AXValueCreate(.cgPoint, &point))
        case kAXSizeAttribute as String:
            var size = CGSize(width: 300, height: 120)
            return (.success, AXValueCreate(.cgSize, &size))
        default: return (.attributeUnsupported, nil)
        }
    }
    var writes = 0
    var writeError = AXError.success
    func replaceSelection(_ element: AXUIElement, text: String) -> AXError {
        writes += 1
        if writeError == .success { self.text = text + self.text }
        return writeError
    }
    func settable(_ element: AXUIElement, _ name: CFString) -> Bool { writable }
    func caret(_ element: AXUIElement, _ range: NSRange) -> (AXError, CGRect?) {
        (.success, CGRect(x: 110, y: 110, width: 0, height: 20))
    }
    func owner(_ element: AXUIElement) -> pid_t? { 4242 }
    func bundleIdentifier(_ pid: pid_t) -> String? { identifier }
}
