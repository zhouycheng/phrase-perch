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
    func captureTarget(id: UUID, pid: pid_t, position: CGPoint, mode: MenuAnchorMode) -> CapturedInputTarget? {
        guard acceptsCapture else { return nil }
        lastMode = mode
        captured = (id, pid)
        readyChecks = 0
        return CapturedInputTarget(
            id: id, caretBounds: mode == .caret ? CGRect(x: 50, y: 100, width: 0, height: 20) : nil)
    }
    func prepareCaptured(pid: pid_t, operationID: UUID) async throws -> PreparedInput {
        if preparationDelay != .zero { try await Task.sleep(for: preparationDelay) }
        guard captured?.0 == operationID, captured?.1 == pid, editable, focusUnchanged, selectionUnchanged else {
            throw InputFailure("输入框或选区已变化")
        }
        return PreparedInput(before: nil, selection: NSRange(location: 0, length: 0))
    }
    func readyToPaste(_ id: UUID) -> Bool {
        readyChecks += 1
        return captured?.0 == id && editable && focusUnchanged && selectionUnchanged
            && (!invalidateBeforeDispatch || readyChecks < 2)
    }
    func readback(_ id: UUID) -> String? { nil }
    func release(_ id: UUID) { if captured?.0 == id { captured = nil } }
}
