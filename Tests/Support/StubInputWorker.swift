import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

actor StubInputWorker: InputTargetWorker {
    private var captured: (UUID, pid_t)?
    var acceptsCapture = true
    var editable = true
    var focusUnchanged = true
    var selectionUnchanged = true
    var invalidateBeforeDispatch = false
    var preparationDelay: Duration = .zero
    private var readyChecks = 0
    private var captureDelay: Duration = .zero
    private var captureCanPaste = true
    private var captureCanDirectWrite = false
    private var captureKind = CapturedInputTarget.FocusKind.editable
    private var before: String?
    private var selection = NSRange(location: 0, length: 0)
    private var readings: [String] = []
    private var readbackDelay: Duration = .zero
    var directSupported = true
    var directFails = false
    func setDirectFailure() { directFails = true }
    private(set) var directWrites: [String] = []
    func setDirectSupported(_ value: Bool) { directSupported = value }
    func focusUnchanged(_ id: UUID) -> Bool { captured?.0 == id && focusUnchanged }
    func readyToWrite(_ id: UUID) -> Bool { directSupported && captured?.0 == id && editable && focusUnchanged && selectionUnchanged }
    func replaceSelection(_ id: UUID, text: String) throws {
        guard readyToWrite(id) else { throw InputFailure("写入条件已变化") }
        directWrites.append(text)
        if directFails { throw InputFailure("AX 写入超时") }
    }
    private(set) var readbackCount = 0
    func setReadback(before: String, selection: NSRange, readings: [String], delay: Duration = .zero) {
        self.before = before
        self.selection = selection
        self.readings = readings
        readbackDelay = delay
    }
    func setCapture(delay: Duration = .zero, canPaste: Bool = true, canDirectWrite: Bool = false, kind: CapturedInputTarget.FocusKind = .editable) {
        captureDelay = delay; captureCanPaste = canPaste; captureCanDirectWrite = canDirectWrite; captureKind = kind
    }

    func configure(
        editable: Bool = true, focusUnchanged: Bool = true, selectionUnchanged: Bool = true,
        invalidateBeforeDispatch: Bool = false, preparationDelay: Duration = .zero
    ) {
        self.editable = editable
        self.focusUnchanged = focusUnchanged
        self.selectionUnchanged = selectionUnchanged
        self.invalidateBeforeDispatch = invalidateBeforeDispatch
        self.preparationDelay = preparationDelay
    }
    private(set) var lastMode: MenuAnchorMode?
    func captureTarget(id: UUID, pid: pid_t, position: CGPoint, mode: MenuAnchorMode) async -> CapturedInputTarget? {
        if captureDelay != .zero { try? await Task.sleep(for: captureDelay) }
        guard acceptsCapture else { return nil }
        lastMode = mode
        captured = (id, pid)
        readyChecks = 0
        var result = CapturedInputTarget(
            id: id, caretBounds: mode == .caret ? CGRect(x: 50, y: 100, width: 0, height: 20) : nil)
        result.canPaste = captureCanPaste
        result.canDirectWrite = captureCanDirectWrite
        result.focusKind = captureKind
        return result
    }
    func prepareCaptured(pid: pid_t, operationID: UUID) async throws -> PreparedInput {
        if preparationDelay != .zero { try await Task.sleep(for: preparationDelay) }
        guard captured?.0 == operationID, captured?.1 == pid, editable, focusUnchanged, selectionUnchanged else {
            throw InputFailure("输入框或选区已变化")
        }
        return PreparedInput(before: before, selection: selection)
    }
    func readyToPaste(_ id: UUID) -> Bool {
        readyChecks += 1
        return captured?.0 == id && editable && focusUnchanged && selectionUnchanged
            && (!invalidateBeforeDispatch || readyChecks < 2)
    }
    func readback(_ id: UUID) async -> String? {
        readbackCount += 1
        if readbackDelay != .zero { try? await Task.sleep(for: readbackDelay) }
        guard !readings.isEmpty else { return nil }
        return readings.count > 1 ? readings.removeFirst() : readings.first
    }
    func release(_ id: UUID) { if captured?.0 == id { captured = nil } }
}
