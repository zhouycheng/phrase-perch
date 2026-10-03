import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

@MainActor @Observable
final class TextInsertionService {
    private(set) var isBusy = false
    private(set) var message = ""
    private(set) var lastResult: InsertionResult?
    private var gate = OperationGate()
    private let worker: any InputTargetWorker
    private let environment: PasteEnvironment
    private let log = Logger(subsystem: "local.FloatingInputBar", category: "input")

    init(worker: any InputTargetWorker = AccessibilityInputWorker(), environment: PasteEnvironment = PasteEnvironment())
    {
        self.worker = worker
        self.environment = environment
    }
    func cancel() { gate.invalidate() }
    func releaseTarget(_ id: UUID) async { await worker.release(id) }
    func captureTarget(
        id: UUID, pid: pid_t, mouse: CGPoint, primaryScreenTop: CGFloat,
        mode: MenuAnchorMode = .mouse
    ) async -> CapturedInputTarget? {
        await worker.captureTarget(
            id: id, pid: pid,
            position: flippedScreenPoint(mouse, primaryScreenTop: primaryScreenTop), mode: mode)
    }

    func insert(_ snippet: Snippet, target: NSRunningApplication, sessionID: UUID) async -> InsertionResult {
        guard let id = gate.begin() else { return .notWritten }
        let generation = gate.generation
        isBusy = true
        message = "正在输入…"
        lastResult = nil
        var result = InsertionResult.notWritten
        var clipboardRevision: Int?
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
            let prepared = try await worker.prepareCaptured(pid: target.processIdentifier, operationID: sessionID)
            guard current(), await worker.readyToPaste(sessionID), current() else { throw InputFailure("输入焦点或选区已变化") }
            clipboardRevision = try environment.copy(snippet.text)
            guard await worker.readyToPaste(sessionID), current(), environment.authorized(),
                environment.clipboardRevision() == clipboardRevision,
                environment.modifiersReleased()
            else {
                throw InputFailure("粘贴前剪贴板或权限已变化")
            }
            guard environment.dispatch() else { throw InputFailure("无法创建粘贴事件") }
            gate.markWriting(id)
            result = .dispatchedUnverified
            if !current(), gate.mayHaveMutated { result = .interruptedAfterDispatch }
            if result == .dispatchedUnverified, let before = prepared.before, let range = prepared.selection,
                range.location <= before.utf16.count, range.length <= before.utf16.count - range.location
            {
                var partial: InsertionResult?
                for _ in 0..<3 {
                    guard current() else {
                        result = .interruptedAfterDispatch
                        break
                    }
                    if let after = await worker.readback(sessionID), current(),
                        let verified = verifyInsertion(before: before, range: range, text: snippet.text, after: after)
                    {
                        if verified == .insertedVerified {
                            result = verified
                            break
                        }
                        partial = verified
                    }
                    try await Task.sleep(for: .milliseconds(80))
                }
                if result == .dispatchedUnverified, let partial { result = partial }
            }
            message =
                result == .dispatchedUnverified
                ? "文案已复制，粘贴操作已发送；请检查目标应用。" : result.message
        } catch {
            result = gate.mayHaveMutated ? .indeterminate : .notWritten
            if !gate.mayHaveMutated, clipboardRevision != nil {
                message = "未自动粘贴：\(error.localizedDescription)。文案已复制。"
            } else {
                message = gate.mayHaveMutated ? result.message : error.localizedDescription
            }
        }
        await worker.release(sessionID)
        gate.finish(id)
        isBusy = false
        lastResult = result
        log.info("Input ended result=\(result.rawValue, privacy: .public)")
        return result
    }
}
