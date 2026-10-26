import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

@MainActor @Observable
final class ContentInsertionService {
    private(set) var isBusy = false
    private(set) var message = ""
    private(set) var lastResult: InsertionResult?
    private var gate = OperationGate()
    private let worker: any InputTargetWorker
    private let environment: PasteEnvironment
    private let retainAttachment: @MainActor (AttachmentReference) async throws -> URL
    private let releaseAttachment: @MainActor (UUID) async -> Void
    private let log = Logger(subsystem: "local.PhrasePerch", category: "input")

    init(worker: any InputTargetWorker = AccessibilityInputWorker(), environment: PasteEnvironment = PasteEnvironment(),
        retainAttachment: @escaping @MainActor (AttachmentReference) async throws -> URL = { _ in throw InputFailure("附件存储不可用") },
        releaseAttachment: @escaping @MainActor (UUID) async -> Void = { _ in })
    {
        self.worker = worker
        self.environment = environment
        self.retainAttachment = retainAttachment
        self.releaseAttachment = releaseAttachment
    }
    func cancel() { gate.invalidate() }
    func observeTarget(_ handler: @escaping @Sendable (UUID) -> Void) async {
        await worker.setInvalidationHandler(handler)
    }
    func releaseTarget(_ id: UUID) async { await worker.release(id) }
    func captureTarget(
        id: UUID, pid: pid_t, mouse: CGPoint, primaryScreenTop: CGFloat,
        mode: MenuAnchorMode = .mouse
    ) async -> CapturedInputTarget? {
        try? await capture(id: id, pid: pid, mouse: mouse, primaryScreenTop: primaryScreenTop, mode: mode)
    }
    func capture(
        id: UUID, pid: pid_t, mouse: CGPoint, primaryScreenTop: CGFloat, mode: MenuAnchorMode
    ) async throws -> CapturedInputTarget? {
        try await worker.captureTarget(
            id: id, pid: pid,
            position: flippedScreenPoint(mouse, primaryScreenTop: primaryScreenTop), mode: mode)
    }

    func focusUnchanged(_ id: UUID) async -> Bool { await worker.focusUnchanged(id) }
    func copyOnly(_ snippet: Snippet) async -> InsertionResult {
        guard let id = gate.begin() else { return .notWritten }
        let generation = gate.generation
        isBusy = true
        var leased: UUID?
        do {
            try SnippetValidator.validate(snippet)
            if let file = snippet.attachment {
                let url = try await retainAttachment(file)
                leased = file.id
                let payload = try await Task.detached { try ClipboardFile(url: url) }.value
                guard gate.isCurrent(id, generation: generation), !Task.isCancelled else { throw CancellationError() }
                _ = try environment.copyFile(payload)
            } else {
                guard !Task.isCancelled else { throw CancellationError() }
                _ = try environment.copy(snippet.text)
            }
            lastResult = .copied
            message = InsertionResult.copied.message
        } catch {
            lastResult = .notWritten
            message = error.localizedDescription
        }
        if let leased { await releaseAttachment(leased) }
        gate.finish(id)
        isBusy = false
        return lastResult ?? .notWritten
    }

    func insert(_ snippet: Snippet, target: NSRunningApplication, sessionID: UUID, copyOnInsert: Bool = true) async -> InsertionResult {
        guard let id = gate.begin() else { return .notWritten }
        let generation = gate.generation
        isBusy = true
        message = "正在输入…"
        lastResult = nil
        var result = InsertionResult.notWritten
        var clipboardRevision: Int?
        var leased: UUID?
        let usesClipboard = snippet.attachment != nil || copyOnInsert
        func current() -> Bool {
            gate.isCurrent(id, generation: generation) && environment.targetIsCurrent(target)
        }
        do {
            try SnippetValidator.validate(snippet)
            guard current() else { throw InputFailure("目标应用已切换") }
            guard environment.modifiersReleased() else {
                throw InputFailure("请松开修饰键后重试")
            }
            guard environment.authorized() else { throw InputFailure("粘贴权限未就绪") }
            let prepared = snippet.attachment == nil
                ? try await worker.prepareCaptured(pid: target.processIdentifier, operationID: sessionID) : PreparedInput()
            if usesClipboard {
                var payload: ClipboardFile?
                if let file = snippet.attachment {
                    let url = try await retainAttachment(file)
                    leased = file.id
                    payload = try await Task.detached { try ClipboardFile(url: url) }.value
                }
                guard current(), await worker.readyToPaste(sessionID), current(), environment.authorized(), environment.modifiersReleased()
                else { throw InputFailure("输入焦点、选区或粘贴条件已变化") }
                try Task.checkCancellation()
                clipboardRevision = try payload.map { try environment.copyFile($0) } ?? environment.copy(snippet.text)
                guard await worker.readyToPaste(sessionID), current(), environment.authorized(),
                    environment.clipboardRevision() == clipboardRevision, environment.modifiersReleased()
                else { throw InputFailure("粘贴前剪贴板或权限已变化") }
                try Task.checkCancellation()
                guard environment.dispatch() else { throw InputFailure("无法创建粘贴事件") }
                gate.markWriting(id)
            } else {
                guard await worker.readyToWrite(sessionID), current(), environment.authorized(), environment.modifiersReleased()
                else { throw InputFailure("当前输入框不支持直接写入，可在设置中开启粘贴插入") }
                try Task.checkCancellation()
                // AX can time out after the editor has accepted the write; never retry this mutation.
                gate.markWriting(id)
                try await worker.replaceSelection(sessionID, text: snippet.text)
            }
            result = .dispatchedUnverified
            if !current(), gate.mayHaveMutated { result = .interruptedAfterDispatch }
            if snippet.attachment == nil, result == .dispatchedUnverified, let before = prepared.before, let range = prepared.selection,
                range.location <= before.utf16.count, range.length <= before.utf16.count - range.location
            {
                var partial: InsertionResult?
                let deadline = ContinuousClock.now.advanced(by: .seconds(1))
                for _ in 0..<10 {
                    guard ContinuousClock.now < deadline else { break }
                    try await Task.sleep(until: min(deadline, ContinuousClock.now.advanced(by: .milliseconds(100))), clock: .continuous)
                    guard current() else {
                        result = .interruptedAfterDispatch
                        break
                    }
                    guard ContinuousClock.now < deadline else { break }
                    if let after = await readback(sessionID, until: deadline), current(),
                        let verified = verifyInsertion(before: before, range: range, text: snippet.text, after: after)
                    {
                        if verified == .insertedVerified {
                            result = verified
                            break
                        }
                        partial = verified
                    }
                }
                if result == .dispatchedUnverified, let partial { result = partial }
            }
            message =
                result == .dispatchedUnverified
                ? (snippet.attachment != nil ? "附件已复制，粘贴操作已发送；请检查目标应用。"
                    : (copyOnInsert ? "文案已复制，粘贴操作已发送；请检查目标应用。" : "写入操作已执行，请检查目标应用。")) : result.message
        } catch {
            result = gate.mayHaveMutated ? .indeterminate : .notWritten
            if !gate.mayHaveMutated, clipboardRevision != nil {
                message = "未自动粘贴：\(error.localizedDescription)。\(snippet.attachment == nil ? "文案" : "附件")已复制。"
            } else {
                message = gate.mayHaveMutated ? "\(result.message)（\(error.localizedDescription)）" : error.localizedDescription
            }
        }
        if let leased { await releaseAttachment(leased) }
        await worker.release(sessionID)
        gate.finish(id)
        isBusy = false
        lastResult = result
        log.info("Input ended result=\(result.rawValue, privacy: .public)")
        return result
    }

    private func readback(_ id: UUID, until deadline: ContinuousClock.Instant) async -> String? {
        let (stream, continuation) = AsyncStream<String?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let query = Task {
            let value = await worker.readback(id)
            if !Task.isCancelled, ContinuousClock.now < deadline { continuation.yield(value) }
            continuation.finish()
        }
        let timeout = Task {
            try? await Task.sleep(until: deadline, clock: .continuous)
            continuation.finish()
        }
        defer {
            query.cancel()
            timeout.cancel()
            continuation.finish()
        }
        // A synchronous AX message finishes on its own timeout; late readback only loses its consumer.
        for await value in stream { return value }
        return nil
    }
}
