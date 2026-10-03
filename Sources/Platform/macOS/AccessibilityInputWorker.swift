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
        guard let object = value(app, kAXFocusedUIElementAttribute as CFString),
            CFGetTypeID(object) == AXUIElementGetTypeID()
        else { return nil }
        let target = unsafeDowncast(object, to: AXUIElement.self)
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
    func captureTarget(id: UUID, pid: pid_t, position: CGPoint, mode: MenuAnchorMode) -> CapturedInputTarget? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(), let editor = focused(pid),
            (try? validateEditor(editor)) != nil, let selection = selectedRange(editor)
        else { return nil }
        if mode == .mouse && !mouseHitsEditor(editor, pid: pid, position: position) { return nil }
        // Retain the input before showing a panel; never recapture at release.
        element = editor
        self.pid = pid
        operationID = id
        originalSelection = selection
        return CapturedInputTarget(
            id: id, caretBounds: mode == .caret ? caretBounds(editor, selection: selection) : nil)
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
        try validateEditor(element)
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
        }
    }
}
