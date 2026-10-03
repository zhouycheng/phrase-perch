import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

protocol InputTargetWorker: Sendable {
    func captureTarget(id: UUID, pid: pid_t, position: CGPoint, mode: MenuAnchorMode) async -> CapturedInputTarget?
    func prepareCaptured(pid: pid_t, operationID: UUID) async throws -> PreparedInput
    func readyToPaste(_ id: UUID) async -> Bool
    func readback(_ id: UUID) async -> String?
    func release(_ id: UUID) async
}
