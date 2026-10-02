import AppKit
import ApplicationServices
import Carbon
import Observation
import OSLog

struct PreparedInput: Sendable {
    var before: String?
    var selection: NSRange?
}

func isOrdinaryTextInput(role: String?, subrole: String?, enabled: Bool?) -> Bool {
    // AppKit NSTextView omits AXEnabled. Missing is not the same as disabled;
    // prepare still requires a positively writable text attribute below.
    enabled != false && subrole != kAXSecureTextFieldSubrole as String &&
    [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role ?? "")
}

@MainActor
func copySnippetToClipboard(_ text: String, pasteboard: NSPasteboard = .general) throws -> Int {
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else { throw InputFailure("剪贴板写入失败，未粘贴") }
    return pasteboard.changeCount
}

let clipboardPasteEventTag: Int64 = 0x464942

func pasteKeyEvents() -> (CGEvent, CGEvent)? {
    guard let source = CGEventSource(stateID: .privateState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return nil }
    down.flags = .maskCommand; up.flags = .maskCommand
    down.setIntegerValueField(.eventSourceUserData, value: clipboardPasteEventTag)
    up.setIntegerValueField(.eventSourceUserData, value: clipboardPasteEventTag)
    return (down, up)
}

// AX references stay inside this actor; no CF object crosses an isolation boundary.
actor AXWorker {
    private var gesture: (id: UUID, pid: pid_t, editor: AXUIElement)?
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
              CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        let target = unsafeDowncast(object, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(target, 0.4)
        return target
    }
    private func selectedRange(_ target: AXUIElement) -> NSRange? {
        guard let raw = value(target, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let ax = unsafeDowncast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private func validateEditor(_ target: AXUIElement) throws {
        guard isOrdinaryTextInput(role: value(target, kAXRoleAttribute as CFString) as? String,
                                  subrole: value(target, kAXSubroleAttribute as CFString) as? String,
                                  enabled: value(target, kAXEnabledAttribute as CFString) as? Bool) else {
            throw InputFailure("当前输入位置暂不支持；密码框、只读或未知位置不会写入")
        }
        guard settable(target, kAXSelectedTextAttribute as CFString) ||
              (settable(target, kAXValueAttribute as CFString) && selectedRange(target) != nil) else {
            throw InputFailure("无法确认当前控件可编辑")
        }
    }
    func captureGesture(id: UUID, pid: pid_t, position: CGPoint) -> Bool {
        gesture = nil
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(position.x), Float(position.y), &hit) == .success else { return false }
        for _ in 0..<8 {
            guard let node = hit else { break }
            AXUIElementSetMessagingTimeout(node, 0.4)
            if (try? validateEditor(node)) != nil {
                gesture = (id, pid, node)
                return true
            }
            guard let parent = value(node, kAXParentAttribute as CFString),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            hit = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return false
    }
    func finishGesture(id: UUID, pid: pid_t, state: ModifierGesture) -> Bool {
        guard let captured = gesture, captured.id == id else { return false }
        defer { gesture = nil }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(), captured.pid == pid,
              let current = focused(pid), (try? validateEditor(current)) != nil else { return false }
        return state.acceptsEditor(sameEditor: CFEqual(captured.editor, current),
                                   selectionLength: selectedRange(current)?.length)
    }
    func canShowMenu(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(), let target = focused(pid),
              (try? validateEditor(target)) != nil else { return false }
        return true
    }
    func prepare(pid: pid_t, operationID: UUID) throws -> PreparedInput {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(), let target = focused(pid) else {
            throw InputFailure("请授权辅助功能，并将光标放到普通输入位置")
        }
        self.element = target; self.pid = pid; self.operationID = operationID
        try validateEditor(target)
        originalSelection = selectedRange(target)
        return PreparedInput(before: value(target, kAXValueAttribute as CFString) as? String,
                             selection: originalSelection)
    }
    func isFocused(_ id: UUID) -> Bool {
        guard id == operationID, let element, AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let current = focused(pid) else { return false }
        return CFEqual(element, current)
    }
    func readyToPaste(_ id: UUID) -> Bool {
        guard let element, isFocused(id) else { return false }
        return selectedRange(element) == originalSelection
    }
    func readback(_ id: UUID) -> String? {
        guard id == operationID, let element, isFocused(id) else { return nil }
        return value(element, kAXValueAttribute as CFString) as? String
    }
    func release(_ id: UUID) {
        if operationID == id { element = nil; operationID = nil }
    }
}

@MainActor @Observable
final class TextInsertionService {
    private(set) var isBusy = false
    private(set) var message = ""
    private(set) var lastResult: InsertionResult?
    private var gate = OperationGate()
    private let worker = AXWorker()
    private let log = Logger(subsystem: "local.FloatingInputBar", category: "input")

    func cancel() { gate.invalidate() }

    func captureGesture(id: UUID, pid: pid_t, mouse: CGPoint, primaryScreenTop: CGFloat) async -> Bool {
        await worker.captureGesture(id: id, pid: pid,
            position: flippedScreenPoint(mouse, primaryScreenTop: primaryScreenTop))
    }
    func finishGesture(id: UUID, pid: pid_t, state: ModifierGesture) async -> Bool {
        await worker.finishGesture(id: id, pid: pid, state: state)
    }

    func canShowMenu(pid: pid_t) async -> Bool {
        await worker.canShowMenu(pid: pid)
    }

    func insert(_ snippet: Snippet, target: NSRunningApplication) async -> InsertionResult {
        guard let id = gate.begin() else { return .notWritten }
        let generation = gate.generation
        isBusy = true; message = "正在输入…"; lastResult = nil
        var result = InsertionResult.notWritten
        var clipboardRevision: Int?
        func current() -> Bool {
            gate.isCurrent(id, generation: generation) && !target.isTerminated &&
            NSWorkspace.shared.frontmostApplication?.isEqual(target) == true
        }
        do {
            try validateSnippet(snippet)
            guard current() else { throw InputFailure("目标应用已切换") }
            guard NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                throw InputFailure("请松开修饰键后重试")
            }
            clipboardRevision = try copySnippetToClipboard(snippet.text)
            guard CGPreflightPostEventAccess() else { throw InputFailure("粘贴权限未就绪") }
            let prepared = try await worker.prepare(pid: target.processIdentifier, operationID: id)
            guard current(), await worker.readyToPaste(id), current() else { throw InputFailure("输入焦点或选区已变化") }
            guard let (down, up) = pasteKeyEvents(), CGPreflightPostEventAccess(), !IsSecureEventInputEnabled(),
                  NSPasteboard.general.changeCount == clipboardRevision,
                  NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                throw InputFailure("粘贴前剪贴板或权限已变化")
            }
            gate.markWriting(id)
            down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
            result = .dispatchedUnverified
            if !current(), gate.mayHaveMutated { result = .interruptedAfterDispatch }
            if result == .dispatchedUnverified, let before = prepared.before, let range = prepared.selection,
               range.location <= before.utf16.count, range.length <= before.utf16.count - range.location {
                var partial: InsertionResult?
                for _ in 0..<3 {
                    guard current() else { result = .interruptedAfterDispatch; break }
                    if let after = await worker.readback(id), current(),
                       let verified = verifyInsertion(before: before, range: range, text: snippet.text, after: after) {
                        if verified == .insertedVerified { result = verified; break }
                        partial = verified
                    }
                    try await Task.sleep(for: .milliseconds(80))
                }
                if result == .dispatchedUnverified, let partial { result = partial }
            }
            message = result == .dispatchedUnverified
                ? "已复制并发送粘贴，请查看目标应用" : result.message
        } catch {
            result = gate.mayHaveMutated ? .indeterminate : .notWritten
            if !gate.mayHaveMutated, clipboardRevision != nil {
                message = "未自动粘贴：\(error.localizedDescription)。文案已复制。"
            } else { message = gate.mayHaveMutated ? result.message : error.localizedDescription }
        }
        await worker.release(id)
        gate.finish(id); isBusy = false; lastResult = result
        log.info("Input ended result=\(result.rawValue, privacy: .public)")
        return result
    }
}
