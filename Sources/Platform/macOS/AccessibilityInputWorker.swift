import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

actor AccessibilityInputWorker: InputTargetWorker {
    private var element: AXUIElement?
    private var operationID: UUID?
    private var pid: pid_t = 0
    private var originalSelection: NSRange?
    private let log = Logger(subsystem: "local.FloatingInputBar", category: "input-target")

    private func value(_ object: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(object, attribute, &result) == .success else { return nil }
        return result
    }
    private func settable(_ object: AXUIElement, _ attribute: CFString) -> Bool {
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(object, attribute, &flag) == .success && flag.boolValue
    }
    private func focused(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.4)
        let appFocus = value(app, kAXFocusedUIElementAttribute as CFString)
        guard let object = appFocus ?? value(system, kAXFocusedUIElementAttribute as CFString),
            CFGetTypeID(object) == AXUIElementGetTypeID()
        else { return nil }
        let target = unsafeDowncast(object, to: AXUIElement.self)
        if appFocus == nil {
            var targetPID: pid_t = 0
            guard AXUIElementGetPid(target, &targetPID) == .success, targetPID == pid else { return nil }
        }
        AXUIElementSetMessagingTimeout(target, 0.4)
        return target
    }
    private func selectedRange(_ target: AXUIElement) -> NSRange? {
        guard let raw = value(target, kAXSelectedTextRangeAttribute as CFString),
            CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let ax = unsafeDowncast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range),
            range.location >= 0, range.length >= 0
        else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private func validateEditor(_ target: AXUIElement) throws {
        guard
            isOrdinaryTextInput(
                role: value(target, kAXRoleAttribute as CFString) as? String,
                subrole: value(target, kAXSubroleAttribute as CFString) as? String,
                enabled: value(target, kAXEnabledAttribute as CFString) as? Bool)
        else {
            throw InputFailure("当前输入位置暂不支持；密码框、只读或未知位置不会写入")
        }
        guard
            settable(target, kAXSelectedTextAttribute as CFString)
                || (settable(target, kAXValueAttribute as CFString) && selectedRange(target) != nil)
        else {
            throw InputFailure("无法确认当前控件可编辑")
        }
    }
    private func caretBounds(_ editor: AXUIElement, selection: NSRange) -> CGRect? {
        guard selection.length <= Int.max - selection.location else { return nil }
        var range = CFRange(location: selection.location + selection.length, length: 0)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                editor, kAXBoundsForRangeParameterizedAttribute as CFString,
                parameter, &result) == .success,
            let result, CFGetTypeID(result) == AXValueGetTypeID()
        else { return nil }
        let ax = unsafeDowncast(result, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(ax) == .cgRect, AXValueGetValue(ax, .cgRect, &rect) else { return nil }
        return rect
    }
    private func editorBounds(_ editor: AXUIElement) -> CGRect? {
        guard let position = value(editor, kAXPositionAttribute as CFString),
            let size = value(editor, kAXSizeAttribute as CFString),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
            AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions)
        else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
    func captureTarget(id: UUID, pid: pid_t, position: CGPoint, mode: MenuAnchorMode) -> CapturedInputTarget? {
        guard !Task.isCancelled, AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            log.info("Capture rejected: cancelled or input authorization unavailable")
            return nil
        }
        guard let editor = focused(pid) else {
            log.info("Capture rejected: focused element unavailable")
            return nil
        }
        do { try validateEditor(editor) } catch {
            log.info("Capture rejected: editor is not an ordinary writable input")
            return nil
        }
        guard let selection = selectedRange(editor) else {
            log.info("Capture rejected: text selection unavailable")
            return nil
        }
        if mode == .mouse && !mouseHitsEditor(editor, pid: pid, position: position) {
            log.info("Capture rejected: pointer is outside the focused input")
            return nil
        }
        let caret = mode == .caret ? caretBounds(editor, selection: selection) : nil
        let bounds = mode == .caret ? editorBounds(editor) : nil
        guard !Task.isCancelled, let current = focused(pid), CFEqual(editor, current),
            selectedRange(editor) == selection
        else {
            log.info("Capture rejected: cancelled or focus or selection changed")
            return nil
        }
        // Retain the input before showing a panel; never recapture at release.
        element = editor
        self.pid = pid
        operationID = id
        originalSelection = selection
        return CapturedInputTarget(
            id: id, caretBounds: caret, editorBounds: bounds)
    }
    private func mouseHitsEditor(_ editor: AXUIElement, pid: pid_t, position: CGPoint) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(position.x), Float(position.y), &hit) == .success else {
            return false
        }
        for _ in 0..<8 {
            guard let node = hit else { break }
            AXUIElementSetMessagingTimeout(node, 0.4)
            if CFEqual(node, editor) {
                return true
            }
            guard let parent = value(node, kAXParentAttribute as CFString),
                CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { break }
            hit = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return false
    }
    func prepareCaptured(pid: pid_t, operationID: UUID) throws -> PreparedInput {
        guard self.pid == pid, readyToPaste(operationID), let element else {
            throw InputFailure("原输入框、选区或权限已变化，已取消粘贴")
        }
        return PreparedInput(
            before: value(element, kAXValueAttribute as CFString) as? String,
            selection: originalSelection)
    }
    func isFocused(_ id: UUID) -> Bool {
        guard id == operationID, let element, AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
            let current = focused(pid)
        else { return false }
        return CFEqual(element, current)
    }
    func readyToPaste(_ id: UUID) -> Bool {
        guard let element, isFocused(id) else { return false }
        return (try? validateEditor(element)) != nil && selectedRange(element) == originalSelection
    }
    func readback(_ id: UUID) -> String? {
        guard id == operationID, let element, isFocused(id) else { return nil }
        return value(element, kAXValueAttribute as CFString) as? String
    }
    func release(_ id: UUID) {
        if operationID == id {
            element = nil
            operationID = nil
            originalSelection = nil
            pid = 0
        }
    }
}
