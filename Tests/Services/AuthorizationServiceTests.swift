import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class AuthorizationServiceTests: PresentationTestCase {
    @MainActor
    func testRestartFailureKeepsSingleActionAndClearsMarker() async throws {
        for saveSucceeds in [false, true] {
            let suite = "PhrasePerch.Tests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var launches = 0
            var terminations = 0
            let environment = AuthorizationEnvironment(
                snapshot: { (true, false) }, save: { _ in saveSucceeds },
                openSettings: { false },
                relaunch: { _, _ in
                    launches += 1
                    throw InputFailure("test launch failure")
                },
                terminate: { terminations += 1 })
            let coordinator = AuthorizationService(
                store: ConfigurationRepository(
                    directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)),
                guide: StubAuthorizationGuide(), environment: environment, defaults: defaults)
            defer { coordinator.cancelGuidance() }
            for _ in 0..<100 where !coordinator.store.isReady { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(coordinator.store.isReady)
            coordinator.refreshPermissions()
            coordinator.performAuthorizationAction()
            for _ in 0..<100 where coordinator.isRestarting { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(coordinator.isRestarting)
            XCTAssertEqual(coordinator.authorizationStep, .restart)
            XCTAssertEqual(launches, saveSucceeds ? 1 : 0)
            XCTAssertEqual(terminations, 0)
            XCTAssertNil(defaults.string(forKey: AuthorizationService.restartPendingKey))
            XCTAssertFalse(coordinator.restartExitReady)
        }
    }

    @MainActor
    func testFailedRestartReadbackOffersReauthorizationWithoutOverlay() throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Bundle.main.bundlePath, forKey: AuthorizationService.restartPendingKey)
        var opened = 0
        let coordinator = AuthorizationService(
            store: ConfigurationRepository(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)),
            guide: StubAuthorizationGuide(),
            environment: AuthorizationEnvironment(
                snapshot: { (true, false) },
                openSettings: {
                    opened += 1
                    return false
                }), defaults: defaults)
        defer { coordinator.cancelGuidance() }
        coordinator.refreshPermissions()
        XCTAssertEqual(coordinator.authorizationStep, .reauthorize)
        coordinator.performAuthorizationAction()
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(coordinator.authorizationStep, .reauthorize)
        XCTAssertFalse(NSApp.windows.contains { $0.title == "PhrasePerch — 授权引导" })
        XCTAssertFalse(coordinator.notice.contains("等待"))
    }
}
