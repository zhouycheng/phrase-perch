import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

protocol InputTargetWorker: Sendable {
    func setInvalidationHandler(_ handler: @escaping @Sendable (UUID) -> Void) async
    func captureTarget(id: UUID, pid: pid_t, position: CGPoint, mode: MenuAnchorMode) async throws -> CapturedInputTarget?
    func prepareCaptured(pid: pid_t, operationID: UUID) async throws -> PreparedInput
    func readyToPaste(_ id: UUID) async -> Bool
    func focusUnchanged(_ id: UUID) async -> Bool
    func readyToWrite(_ id: UUID) async -> Bool
    func replaceSelection(_ id: UUID, text: String) async throws
    func readback(_ id: UUID) async -> String?
    func release(_ id: UUID) async
}

extension InputTargetWorker {
    func setInvalidationHandler(_ handler: @escaping @Sendable (UUID) -> Void) async {}
}
