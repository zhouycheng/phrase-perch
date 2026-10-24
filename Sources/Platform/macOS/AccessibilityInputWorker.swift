import AppKit
import ApplicationServices
import Carbon

actor AccessibilityInputWorker: InputTargetWorker {
    private let access: any AccessibilityAccess
    init(access: any AccessibilityAccess = SystemAccessibilityAccess()) { self.access = access }
    private var element: AXUIElement?
    private var originalFocus: AXUIElement?
    private var operationID: UUID?
    private var pid: pid_t = 0
    private var originalSelection: NSRange?
    private var observation: AXFocusObservation?
    private var onInvalidated: (@Sendable (UUID) -> Void)?
    private var captureError: AXError?
    private var lastError: AXError = .success
    private var cachedCaret: (element: AXUIElement, selection: NSRange, visible: NSRange, bounds: CGRect, caret: CGRect)?

    func setInvalidationHandler(_ handler: @escaping @Sendable (UUID) -> Void) {
        onInvalidated = handler
    }
    private func value(_ object: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        guard !Task.isCancelled else { return nil }
        let (error, result) = access.attribute(object, attribute)
        if error != .success {
            lastError = error
            if error != .attributeUnsupported && error != .noValue { captureError = error }
            return nil
        }
        return result
    }
    private func object(_ raw: CFTypeRef?) -> AXUIElement? {
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }
    private func focused(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        let raw = value(app, kAXFocusedUIElementAttribute as CFString)
        if raw == nil, lastError == .cannotComplete { return nil }
        guard let target = object(raw) else { return nil }
        guard access.owner(target) == pid else { return nil }
        return target
    }
    private func selectedRange(_ target: AXUIElement, attribute: CFString = kAXSelectedTextRangeAttribute as CFString) -> NSRange? {
        guard let raw = value(target, attribute),
            CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let ax = unsafeDowncast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range),
            range.location >= 0, range.length >= 0, range.length <= Int.max - range.location else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private func isSecure(_ target: AXUIElement) -> Bool {
        value(target, kAXSubroleAttribute as CFString) as? String == kAXSecureTextFieldSubrole as String
            || value(target, kAXRoleAttribute as CFString) as? String == kAXSecureTextFieldSubrole as String
    }
    private func ordinary(_ target: AXUIElement) -> Bool {
        isOrdinaryTextInput(
            role: value(target, kAXRoleAttribute as CFString) as? String,
            subrole: value(target, kAXSubroleAttribute as CFString) as? String,
            enabled: value(target, kAXEnabledAttribute as CFString) as? Bool)
            && value(target, "AXReadOnly" as CFString) as? Bool != true
    }
    private func settable(_ target: AXUIElement, _ attribute: CFString) -> Bool {
        guard !Task.isCancelled else { return false }
        return access.settable(target, attribute)
    }
    private func permitsPaste(_ target: AXUIElement, pid: pid_t) -> Bool {
        guard access.owner(target) == pid, ordinary(target) else { return false }
        if settable(target, kAXValueAttribute as CFString) {
            return true
        }
        if TextInputEligibility.supportsPasteAdapter(access.bundleIdentifier(pid)) {
            guard let editable = object(value(target, "AXEditableAncestor" as CFString)) else { return false }
            return CFEqual(editable, target)
        }
        return settable(target, kAXSelectedTextAttribute as CFString)
    }
    private func resolveEditor(_ focus: AXUIElement, pid: pid_t) throws -> AXUIElement? {
        var node: AXUIElement? = focus
        var candidate: AXUIElement?
        // Only inspect the focused lineage; siblings may be unrelated input targets.
        for _ in 0..<5 {
            try Task.checkCancellation()
            guard let current = node else { break }
            if isSecure(current) { throw InputCaptureFailure.secureInput }
            if candidate == nil, ordinary(current) { candidate = current }
            node = object(value(current, kAXParentAttribute as CFString))
            if !TextInputEligibility.supportsPasteAdapter(access.bundleIdentifier(pid)) {
                break
            }
        }
        return candidate
    }
    private func caretBounds(_ editor: AXUIElement, selection: NSRange) -> CGRect? {
        guard !Task.isCancelled else { return nil }
        let (error, rect) = access.caret(editor, selection)
        if error != .success { lastError = error }
        return rect
    }

    private func editorBounds(_ editor: AXUIElement) -> CGRect? {
        guard let position = value(editor, kAXPositionAttribute as CFString),
            let size = value(editor, kAXSizeAttribute as CFString),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
            AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
    func captureTarget(id: UUID, pid: pid_t, position: CGPoint, mode: MenuAnchorMode) async throws -> CapturedInputTarget? {
        for attempt in 0..<2 {
            do { return try capture(id: id, pid: pid, mode: mode) }
            catch InputCaptureFailure.unavailable(let code) where attempt == 0 && code == AXError.cannotComplete.rawValue {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        return nil
    }
    private func capture(id: UUID, pid: pid_t, mode: MenuAnchorMode) throws -> CapturedInputTarget {
        try Task.checkCancellation()
        guard access.trusted else { throw InputCaptureFailure.authorization }
        guard !access.secureInput else { throw InputCaptureFailure.secureInput }
        lastError = .success
        captureError = nil
        guard let focus = focused(pid) else {
            guard lastError == .noValue else { throw InputCaptureFailure.unavailable(lastError.rawValue) }
            lastError = .success
            guard focused(pid) == nil, lastError == .noValue else { throw InputCaptureFailure.changed }
            self.pid = pid; operationID = id; element = nil; originalFocus = nil; originalSelection = nil; observation = nil
            var captured = CapturedInputTarget(id: id, caretBounds: nil)
            captured.canPaste = false
            captured.focusKind = .nonInput
            captured.detail = "复制模式"
            return captured
        }
        let editor = try resolveEditor(focus, pid: pid)
        lastError = .success
        let selection = editor.flatMap { selectedRange($0) }
        if selection == nil, lastError == .cannotComplete {
            throw InputCaptureFailure.unavailable(lastError.rawValue)
        }
        let visible = editor.flatMap { selectedRange($0, attribute: kAXVisibleCharacterRangeAttribute as CFString) }
        let bounds = editor.flatMap(editorBounds)
        var caret = mode == .caret ? editor.flatMap { node in selection.flatMap { caretBounds(node, selection: $0) } } : nil
        if let rect = caret, !rect.origin.x.isFinite || !rect.origin.y.isFinite || !rect.width.isFinite
            || !rect.height.isFinite || rect.width < 0 || rect.height <= 0
            || bounds.map({ !$0.insetBy(dx: -2, dy: -2).contains(CGPoint(x: rect.midX, y: rect.midY)) || rect.height > $0.height + 4 }) == true {
            caret = nil
        }
        var usedCache = false
        if caret == nil, mode == .caret, let editor, let selection, let bounds, let cached = cachedCaret,
            observation?.changed == false, observation?.tracksSelection == true,
            visible == cached.visible, CFEqual(editor, cached.element), selection == cached.selection, bounds == cached.bounds {
            caret = cached.caret
            usedCache = true
        }
        guard let current = focused(pid), CFEqual(focus, current) else { throw InputCaptureFailure.changed }
        if let editor, selectedRange(editor) != selection { throw InputCaptureFailure.changed }
        try Task.checkCancellation()
        let canPaste = editor.map { permitsPaste($0, pid: pid) } == true && selection != nil
        try Task.checkCancellation()
        self.element = editor
        originalFocus = focus
        self.pid = pid
        operationID = id
        originalSelection = selection
        observation = nil
        if let editor {
            let callback = onInvalidated
            if access.observesChanges {
                observation = AXFocusObservation(pid: pid, app: AXUIElementCreateApplication(pid), editor: editor,
                    window: object(value(editor, kAXWindowAttribute as CFString))) {
                    callback?(id)
                }
            }
            if let caret, let selection, let visible, let bounds {
                cachedCaret = (editor, selection, visible, bounds, caret)
            } else { cachedCaret = nil }
        } else { cachedCaret = nil }
        try Task.checkCancellation()
        var captured = CapturedInputTarget(id: id, caretBounds: caret, editorBounds: bounds)
        captured.canPaste = canPaste
        captured.canDirectWrite = editor.map { ordinary($0) && settable($0, kAXSelectedTextAttribute as CFString) } == true && selection != nil
        let role = value(focus, kAXRoleAttribute as CFString) as? String
        captured.focusKind = editor != nil && selection != nil ? .editable : (["AXButton", "AXWindow", "AXStaticText", "AXScrollArea", "AXWebArea"].contains(role ?? "") ? .nonInput : .unknown)
        captured.usedCachedCaret = usedCache
        captured.detail = canPaste || captured.canDirectWrite ? "" : "复制模式"
        if let error = captureError { throw InputCaptureFailure.unavailable(error.rawValue) }
        return captured
    }
    func prepareCaptured(pid: pid_t, operationID: UUID) throws -> PreparedInput {
        guard self.pid == pid, (readyToPaste(operationID) || readyToWrite(operationID)), let element else {
            throw InputFailure("原输入框、选区或权限已变化，已取消粘贴")
        }
        return PreparedInput(before: value(element, kAXValueAttribute as CFString) as? String, selection: originalSelection)
    }
    func focusUnchanged(_ id: UUID) -> Bool {
        guard operationID == id, access.trusted, !access.secureInput else { return false }
        if originalFocus != nil { return isFocused(id) }
        lastError = .success
        return focused(pid) == nil && lastError == .noValue
    }
    func isFocused(_ id: UUID) -> Bool {
        guard id == operationID, let originalFocus, access.trusted, !access.secureInput,
            let current = focused(pid) else { return false }
        return CFEqual(originalFocus, current)
    }
    func readyToPaste(_ id: UUID) -> Bool {
        guard let element, originalSelection != nil, isFocused(id) else { return false }
        return permitsPaste(element, pid: pid) && selectedRange(element) == originalSelection
    }
    func readyToWrite(_ id: UUID) -> Bool {
        guard let element, originalSelection != nil, isFocused(id), ordinary(element),
            access.owner(element) == pid, selectedRange(element) == originalSelection else { return false }
        return settable(element, kAXSelectedTextAttribute as CFString)
    }
    func replaceSelection(_ id: UUID, text: String) throws {
        try Task.checkCancellation()
        guard readyToWrite(id), let element else { throw InputFailure("当前输入框不支持直接写入，可在设置中开启粘贴插入") }
        try Task.checkCancellation()
        let error = access.replaceSelection(element, text: text)
        guard error == .success else { throw InputCaptureFailure.unavailable(error.rawValue) }
    }
    func readback(_ id: UUID) -> String? {
        guard id == operationID, let element, isFocused(id) else { return nil }
        return value(element, kAXValueAttribute as CFString) as? String
    }
    func release(_ id: UUID) {
        if operationID == id {
            element = nil
            originalFocus = nil
            operationID = nil
            originalSelection = nil
            pid = 0
        }
    }
}
