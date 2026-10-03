import CoreGraphics
import Foundation

@MainActor
func waitForModifierRelease(
    timeout: Duration = HoldMenuSession.modifierReleaseTimeout,
    released: () -> Bool, current: () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !released() {
        guard !Task.isCancelled, current(), clock.now < deadline else { return false }
        do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
    }
    return !Task.isCancelled && current()
}
