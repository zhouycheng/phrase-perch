import AppKit
import ApplicationServices
import Carbon

protocol AccessibilityAccess: Sendable {
    var trusted: Bool { get }
    var secureInput: Bool { get }
    func attribute(_ element: AXUIElement, _ name: CFString) -> (AXError, CFTypeRef?)
    func replaceSelection(_ element: AXUIElement, text: String) -> AXError
    func settable(_ element: AXUIElement, _ name: CFString) -> Bool
    func caret(_ element: AXUIElement, _ range: NSRange) -> (AXError, CGRect?)
    func owner(_ element: AXUIElement) -> pid_t?
    func bundleIdentifier(_ pid: pid_t) -> String?
    var observesChanges: Bool { get }
}

struct SystemAccessibilityAccess: AccessibilityAccess {
    var trusted: Bool { AXIsProcessTrusted() }
    var secureInput: Bool { IsSecureEventInputEnabled() }
    var observesChanges: Bool { true }
    func attribute(_ element: AXUIElement, _ name: CFString) -> (AXError, CFTypeRef?) {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &result)
        return (error, result)
    }
    func replaceSelection(_ element: AXUIElement, text: String) -> AXError {
        AXUIElementSetMessagingTimeout(element, 0.1)
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
    }
    func settable(_ element: AXUIElement, _ name: CFString) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name, &flag) == .success && flag.boolValue
    }
    func caret(_ element: AXUIElement, _ selection: NSRange) -> (AXError, CGRect?) {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var range = CFRange(location: selection.location + selection.length, length: 0)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return (.illegalArgument, nil) }
        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element,
            kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result)
        guard error == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return (error, nil) }
        let ax = unsafeDowncast(result, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(ax) == .cgRect, AXValueGetValue(ax, .cgRect, &rect) else { return (.failure, nil) }
        return (.success, rect)
    }
    func owner(_ element: AXUIElement) -> pid_t? {
        var owner: pid_t = 0
        return AXUIElementGetPid(element, &owner) == .success ? owner : nil
    }
    func bundleIdentifier(_ pid: pid_t) -> String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }
}
