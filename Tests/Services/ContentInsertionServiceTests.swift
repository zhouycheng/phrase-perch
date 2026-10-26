import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class ContentInsertionServiceTests: PresentationTestCase {
    @MainActor
    func testDelayedReadbackAndPartialInsertionNeverResend() async {
        let text = "中文 👩🏽‍💻\n第二行"
        for complete in [true, false] {
            let worker = StubInputWorker()
            let system = StubPasteSystem()
            let service = ContentInsertionService(worker: worker, environment: system.environment)
            let token = UUID()
            let target = NSRunningApplication.current
            await worker.setReadback(
                before: "前原文后", selection: NSRange(location: 1, length: 2),
                readings: complete ? ["前原文后", "前中后", "前\(text)后"] : ["前中后"])
            _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
            let result = await service.insert(Snippet(title: "测试", text: text), target: target, sessionID: token)
            XCTAssertEqual(result, complete ? .insertedVerified : .partialVerified)
            XCTAssertEqual(system.dispatches, 1)
            XCTAssertEqual(system.copies, [text])
            let reads = await worker.readbackCount
            if complete { XCTAssertEqual(reads, 3) }
            else { XCTAssertTrue((8...10).contains(reads)) }
        }
    }

    @MainActor
    func testReadbackBudgetDiscardsLateSuccess() async {
        let worker = StubInputWorker()
        let system = StubPasteSystem()
        let service = ContentInsertionService(worker: worker, environment: system.environment)
        let token = UUID()
        let target = NSRunningApplication.current
        await worker.setReadback(before: "", selection: NSRange(location: 0, length: 0),
            readings: ["测试"], delay: .seconds(2))
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        let started = ContinuousClock.now
        let result = await service.insert(Snippet(title: "测试", text: "测试"), target: target, sessionID: token)
        XCTAssertEqual(result, .dispatchedUnverified)
        XCTAssertLessThan(started.duration(to: .now), .milliseconds(1400))
        XCTAssertFalse(service.isBusy)
        await Task.yield()
        XCTAssertEqual(service.lastResult, .dispatchedUnverified)
        XCTAssertEqual(system.dispatches, 1)
    }

    @MainActor
    func testCancellationAfterDispatchReportsUncertainResultOnce() async {
        let worker = StubInputWorker()
        let system = StubPasteSystem()
        let service = ContentInsertionService(worker: worker, environment: system.environment)
        let token = UUID()
        let target = NSRunningApplication.current
        await worker.setReadback(before: "", selection: NSRange(location: 0, length: 0), readings: [""])
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        let task = Task { await service.insert(Snippet(title: "测试", text: "测试"), target: target, sessionID: token) }
        while system.dispatches == 0 { await Task.yield() }
        service.cancel()
        let result = await task.value
        XCTAssertEqual(result, .interruptedAfterDispatch)
        XCTAssertEqual(system.dispatches, 1)
    }

    @MainActor
    func testCapturedTargetCannotBeReplacedAtReleaseOrUsedTwice() async {
        let worker = StubInputWorker()
        let system = StubPasteSystem()
        let service = ContentInsertionService(worker: worker, environment: system.environment)
        let original = UUID()
        let replacement = UUID()
        let target = NSRunningApplication.current
        let snippet = Snippet(title: "测试", text: "  中文 👩🏽‍💻\n末尾\t\n")
        let captured = await service.captureTarget(
            id: original, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        XCTAssertNotNil(captured)
        let wrong = await service.insert(snippet, target: target, sessionID: replacement)
        XCTAssertEqual(wrong, .notWritten)
        XCTAssertTrue(system.copies.isEmpty)
        XCTAssertEqual(system.dispatches, 0)
        let result = await service.insert(snippet, target: target, sessionID: original)
        XCTAssertEqual(result, .dispatchedUnverified)
        XCTAssertEqual(system.copies, [snippet.text])
        XCTAssertEqual(system.dispatches, 1)
        let repeated = await service.insert(snippet, target: target, sessionID: original)
        XCTAssertEqual(repeated, .notWritten)
        XCTAssertEqual(system.dispatches, 1)
        XCTAssertEqual(system.copies.count, 1)
    }

    @MainActor
    func testCapturedInputChangesPreventClipboardAndPaste() async {
        for failure in ["application", "editor", "selection", "readonly", "permission", "modifier"] {
            let worker = StubInputWorker()
            let system = StubPasteSystem()
            let service = ContentInsertionService(worker: worker, environment: system.environment)
            let token = UUID()
            let target = NSRunningApplication.current
            _ = await service.captureTarget(
                id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
            switch failure {
            case "application": system.isCurrent = false
            case "editor": await worker.configure(focusUnchanged: false)
            case "selection": await worker.configure(selectionUnchanged: false)
            case "readonly": await worker.configure(editable: false)
            case "permission": system.authorized = false
            default: system.released = false
            }
            let result = await service.insert(Snippet(title: "测试", text: "正文"), target: target, sessionID: token)
            XCTAssertEqual(result, .notWritten, failure)
            XCTAssertTrue(system.copies.isEmpty, failure)
            XCTAssertEqual(system.dispatches, 0, failure)
        }
    }

    @MainActor
    func testClipboardChangeAndFinalFocusCheckPreventDispatch() async {
        for changedClipboard in [false, true] {
            let worker = StubInputWorker()
            let system = StubPasteSystem()
            let service = ContentInsertionService(worker: worker, environment: system.environment)
            let token = UUID()
            let target = NSRunningApplication.current
            _ = await service.captureTarget(
                id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
            system.clipboardChanged = changedClipboard
            await worker.configure(invalidateBeforeDispatch: !changedClipboard)
            let result = await service.insert(Snippet(title: "测试", text: "正文"), target: target, sessionID: token)
            XCTAssertEqual(result, .notWritten)
            XCTAssertEqual(system.copies, ["正文"])
            XCTAssertEqual(system.dispatches, 0)
            XCTAssertTrue(service.message.contains("文案已复制"))
        }
    }

    @MainActor
    func testCancellationDuringPreparationAndConcurrentInsert() async {
        let worker = StubInputWorker()
        let system = StubPasteSystem()
        let service = ContentInsertionService(worker: worker, environment: system.environment)
        let token = UUID()
        let target = NSRunningApplication.current
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        await worker.configure(preparationDelay: .milliseconds(80))
        let snippet = Snippet(title: "测试", text: "正文")
        let first = Task { await service.insert(snippet, target: target, sessionID: token) }
        while !service.isBusy { await Task.yield() }
        let duplicate = await service.insert(snippet, target: target, sessionID: token)
        XCTAssertEqual(duplicate, .notWritten)
        service.cancel()
        let cancelled = await first.value
        XCTAssertEqual(cancelled, .notWritten)
        XCTAssertTrue(system.copies.isEmpty)
        XCTAssertEqual(system.dispatches, 0)
        XCTAssertFalse(service.isBusy)
    }

    @MainActor
    func testFailedEventCreationDoesNotClaimDispatch() async {
        let worker = StubInputWorker()
        let system = StubPasteSystem()
        system.canDispatch = false
        let service = ContentInsertionService(worker: worker, environment: system.environment)
        let token = UUID()
        let target = NSRunningApplication.current
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        let result = await service.insert(Snippet(title: "测试", text: "正文"), target: target, sessionID: token)
        XCTAssertEqual(result, .notWritten)
        XCTAssertEqual(system.dispatches, 0)
    }

    @MainActor
    func testTwentyNativeMenuHoldSelectionsDispatchExactlyOnce() async throws {
        let controller = FloatingMenuWindowController()
        controller.onDismiss = {}
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
            displayName: "Preview",
            buttons: [
                Snippet(title: "继续", text: "继续正文"),
                Snippet(title: "检查", text: "检查正文"),
                Snippet(title: "解释", text: "解释正文"),
            ])
        let point = try unobstructedTestPoint(controller: controller, profile: profile)
        defer { controller.hide() }
        let worker = StubInputWorker()
        let system = StubPasteSystem()
        let service = ContentInsertionService(worker: worker, environment: system.environment)
        let target = NSRunningApplication.current
        var session = HoldMenuSession()
        for iteration in 0..<40 {
            let mode: MenuAnchorMode = iteration < 20 ? .mouse : .caret
            let token = try XCTUnwrap(session.begin(.modifier))
            let captured = await service.captureTarget(
                id: token, pid: target.processIdentifier,
                mouse: point, primaryScreenTop: 900, mode: mode)
            XCTAssertNotNil(captured)
            XCTAssertTrue(session.show(token))
            XCTAssertTrue(
                controller.show(profile: profile, at: point, initialMouse: point, requiresMovement: mode == .caret))
            try await Task.sleep(for: .milliseconds(470))
            let layout = try XCTUnwrap(controller.layout)
            let rect = layout.items[iteration % 3]
            let selectedPoint = CGPoint(x: rect.midX, y: rect.midY)
            XCTAssertEqual(controller.updateSelection(at: selectedPoint), profile.buttons[iteration % 3].id)
            XCTAssertNil(controller.updateSelection(at: point), "Moving back to center clears selection")
            let selected = controller.updateSelection(at: selectedPoint)
            XCTAssertEqual(session.release(.modifier, selection: selected), token)
            controller.hide()
            XCTAssertFalse(controller.isPresented)
            XCTAssertNil(controller.selectedID)
            XCTAssertNil(session.release(.modifier, selection: selected))
            XCTAssertTrue(session.commit(token))
            let result = await service.insert(profile.buttons[iteration % 3], target: target, sessionID: token)
            XCTAssertEqual(result, .dispatchedUnverified)
            XCTAssertEqual(system.dispatches, iteration + 1)
            XCTAssertEqual(system.copies.last, profile.buttons[iteration % 3].text)
            session.cancel()
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(controller.panel.isVisible)
        XCTAssertEqual(system.copies.count, 40)
    }

    @MainActor
    func testCaptureModeAndTargetSnapshotPassThrough() async throws {
        let worker = StubInputWorker()
        let service = ContentInsertionService(worker: worker, environment: StubPasteSystem().environment)
        for mode in MenuAnchorMode.allCases {
            let token = UUID()
            let result = await service.captureTarget(
                id: token, pid: getpid(),
                mouse: CGPoint(x: 500, y: 500), primaryScreenTop: 900, mode: mode)
            let captured = try XCTUnwrap(result)
            XCTAssertEqual(captured.id, token)
            XCTAssertEqual(captured.caretBounds != nil, mode == .caret)
            let recordedMode = await worker.lastMode
            XCTAssertEqual(recordedMode, mode)
        }
    }
}
