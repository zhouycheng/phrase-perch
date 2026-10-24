import CoreGraphics
import Foundation

@MainActor
func waitForModifierRelease(
    timeout: Duration = HoldMenuSession.modifierReleaseTimeout,
    now: () -> ContinuousClock.Instant = { .now },
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    released: () -> Bool, current: () -> Bool
) async -> Bool {
    let deadline = now().advanced(by: timeout)
    while !released() {
        guard !Task.isCancelled, current(), now() < deadline else { return false }
        do { try await sleep(.milliseconds(10)) } catch { return false }
    }
    return !Task.isCancelled && current()
}
