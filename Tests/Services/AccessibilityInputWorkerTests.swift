import AppKit
import ApplicationServices
import XCTest
@testable import PhrasePerch

final class AccessibilityInputWorkerTests: XCTestCase {
    func testSafariAndChatGPTPasteWithoutDirectAXWriteOrMouseHit() async throws {
        for identifier in ["com.apple.Safari", "com.openai.codex", "com.openai.chat"] {
            let access = StubAccessibilityAccess()
            access.identifier = identifier
            access.enabled = nil
            let worker = AccessibilityInputWorker(access: access)
            let id = UUID()
            let captured = try await worker.captureTarget(id: id, pid: 4242,
                position: CGPoint(x: -2000, y: -2000), mode: .mouse)
            XCTAssertEqual(captured?.canPaste, true)
            let ready = await worker.readyToPaste(id)
            XCTAssertTrue(ready)
        }
    }
    func testMissingRangeUnknownDisabledAndReadonlyBecomeCopyOnly() async throws {
        for condition in ["range", "role", "disabled", "readonly", "adapter", "editable"] {
            let access = StubAccessibilityAccess()
            switch condition {
            case "range": access.hasRange = false
            case "role": access.role = "AXGroup"
            case "disabled": access.enabled = false
            case "readonly": access.readOnly = true
            case "editable": access.editableAncestor = false
            default: access.identifier = "unknown"
            }
            let worker = AccessibilityInputWorker(access: access)
            let id = UUID()
            let captured = try await worker.captureTarget(id: id, pid: 4242, position: .zero, mode: .caret)
            XCTAssertEqual(captured?.canPaste, false, condition)
            let ready = await worker.readyToPaste(id)
            XCTAssertFalse(ready)
        }
    }
    func testSecureInputPasswordAndPermissionFailExplicitly() async throws {
        for condition in ["secure", "password", "permission"] {
            let access = StubAccessibilityAccess()
            if condition == "secure" { access.secureInput = true }
            if condition == "password" { access.subrole = kAXSecureTextFieldSubrole as String }
            if condition == "permission" { access.trusted = false }
            let worker = AccessibilityInputWorker(access: access)
            do {
                _ = try await worker.captureTarget(id: UUID(), pid: 4242, position: .zero, mode: .mouse)
                XCTFail("Expected explicit rejection")
            } catch let error as InputCaptureFailure {
                XCTAssertEqual(error, condition == "permission" ? .authorization : .secureInput)
            }
        }
    }
    func testTransientAXErrorRetriesOnceAndPersistentErrorKeepsCode() async throws {
        let access = StubAccessibilityAccess()
        access.failuresRemaining = 1
        let worker = AccessibilityInputWorker(access: access)
        let captured = try await worker.captureTarget(id: UUID(), pid: 4242, position: .zero, mode: .caret)
        XCTAssertNotNil(captured)
        XCTAssertEqual(access.focusReads, 3)
        let failing = StubAccessibilityAccess()
        failing.focusError = .cannotComplete
        do {
            _ = try await AccessibilityInputWorker(access: failing).captureTarget(id: UUID(), pid: 4242, position: .zero, mode: .mouse)
            XCTFail("Expected AX failure")
        } catch let error as InputCaptureFailure {
            XCTAssertEqual(error, .unavailable(AXError.cannotComplete.rawValue))
            XCTAssertEqual(failing.focusReads, 2)
        }
    }
    func testChangedFocusAndReleasedTargetCannotPaste() async throws {
        let access = StubAccessibilityAccess()
        access.changeFocusAfterFirstRead = true
        do {
            _ = try await AccessibilityInputWorker(access: access).captureTarget(id: UUID(), pid: 4242, position: .zero, mode: .mouse)
            XCTFail("Expected changed focus")
        } catch let error as InputCaptureFailure { XCTAssertEqual(error, .changed) }
        let worker = AccessibilityInputWorker(access: StubAccessibilityAccess())
        let id = UUID()
        _ = try await worker.captureTarget(id: id, pid: 4242, position: .zero, mode: .mouse)
        await worker.release(id)
        let ready = await worker.readyToPaste(id)
        XCTAssertFalse(ready)
    }
}
