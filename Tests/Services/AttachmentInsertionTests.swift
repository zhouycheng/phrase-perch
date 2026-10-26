import AppKit
import XCTest
@testable import PhrasePerch

final class AttachmentInsertionTests: XCTestCase {
    @MainActor
    private func fixture() async throws -> (URL, JSONConfigurationStorage, AttachmentReference) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("测试.txt")
        try Data("attachment".utf8).write(to: source)
        let disk = JSONConfigurationStorage(directory: root.appendingPathComponent("store"))
        return (root, disk, try await disk.importAttachment(from: source))
    }
    @MainActor
    func testAttachmentUsesClipboardInDirectModeAndNeverReadsBackOrDispatchesTwice() async throws {
        let (root, disk, file) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = StubInputWorker(), system = StubPasteSystem()
        let service = ContentInsertionService(worker: worker, environment: system.environment,
            retainAttachment: { try await disk.retainAttachment($0) }, releaseAttachment: { await disk.releaseAttachment($0) })
        let token = UUID(), target = NSRunningApplication.current
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        let snippet = Snippet(title: "文件", content: .attachment(file))
        let result = await service.insert(snippet, target: target, sessionID: token, copyOnInsert: false)
        XCTAssertEqual(result, .dispatchedUnverified)
        XCTAssertEqual(system.fileCopies.count, 1)
        XCTAssertTrue(system.copies.isEmpty)
        XCTAssertEqual(system.dispatches, 1)
        let readbacks = await worker.readbackCount, writes = await worker.directWrites
        XCTAssertEqual(readbacks, 0)
        XCTAssertTrue(writes.isEmpty)
        let repeated = await service.insert(snippet, target: target, sessionID: token, copyOnInsert: false)
        XCTAssertEqual(repeated, .notWritten)
        XCTAssertEqual(system.dispatches, 1)
        XCTAssertEqual(system.fileCopies.count, 1)
        let leases = await disk.attachmentLeases
        XCTAssertTrue(leases.isEmpty)
    }
    @MainActor
    func testFocusChangesMissingFilesAndClipboardChangesPreventFileDispatch() async throws {
        for scenario in ["focus", "missing", "clipboard"] {
            let (root, disk, file) = try await fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let worker = StubInputWorker(), system = StubPasteSystem()
            let service = ContentInsertionService(worker: worker, environment: system.environment,
                retainAttachment: { try await disk.retainAttachment($0) }, releaseAttachment: { await disk.releaseAttachment($0) })
            let token = UUID(), target = NSRunningApplication.current
            _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
            if scenario == "focus" { await worker.configure(focusUnchanged: false) }
            if scenario == "missing" { try FileManager.default.removeItem(at: await disk.attachmentURL(file)) }
            if scenario == "clipboard" { system.clipboardChanged = true }
            let result = await service.insert(Snippet(title: "附件", content: .attachment(file)), target: target, sessionID: token)
            XCTAssertEqual(result, .notWritten)
            XCTAssertEqual(system.dispatches, 0)
            XCTAssertEqual(system.fileCopies.count, scenario == "clipboard" ? 1 : 0)
        }
    }
    @MainActor
    func testCancellationDuringFilePreparationAndCopyOnlyReleaseLeases() async throws {
        let (root, disk, file) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = StubInputWorker(), system = StubPasteSystem()
        let service = ContentInsertionService(worker: worker, environment: system.environment,
            retainAttachment: {
                try await Task.sleep(for: .milliseconds(60))
                return try await disk.retainAttachment($0)
            }, releaseAttachment: { await disk.releaseAttachment($0) })
        let token = UUID(), target = NSRunningApplication.current
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        let snippet = Snippet(title: "文件", content: .attachment(file))
        let task = Task { await service.insert(snippet, target: target, sessionID: token) }
        try await Task.sleep(for: .milliseconds(10))
        service.cancel()
        let cancelled = await task.value
        XCTAssertEqual(cancelled, .notWritten)
        XCTAssertTrue(system.fileCopies.isEmpty)
        let copied = await service.copyOnly(snippet)
        XCTAssertEqual(copied, .copied)
        XCTAssertEqual(system.fileCopies.count, 1)
        XCTAssertEqual(system.dispatches, 0)
        let leases = await disk.attachmentLeases
        XCTAssertTrue(leases.isEmpty)
    }
    @MainActor
    func testImageClipboardHasOneFileItemWithOriginalImageBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("image.png")
        let data = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP1sAAAAASUVORK5CYII="))
        try data.write(to: image)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        _ = try ClipboardService.copyFile(ClipboardFile(url: image), pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(ClipboardService.fileURLs(pasteboard: pasteboard), [image])
        XCTAssertEqual(pasteboard.data(forType: .png), data)
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
