import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class AuthorizationServiceTests: PresentationTestCase {
    @MainActor
    func testFirstManualEntryPromptsOncePerProcessAndDefersLoginLaunch() throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var granted = false
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        func service() -> AuthorizationService {
            AuthorizationService(store: store, guide: StubAuthorizationGuide(),
                environment: AuthorizationEnvironment(snapshot: { (granted, granted) }), defaults: defaults)
        }
        let authorization = service()
        var presentations = 0
        authorization.onShowPermissionSetup = { presentations += 1 }
        authorization.checkFirstManualEntry(launchedAtLogin: true)
        XCTAssertEqual(presentations, 0)
        authorization.checkFirstManualEntry(launchedAtLogin: false)
        XCTAssertEqual(presentations, 1)
        for _ in 0..<3 { authorization.checkFirstManualEntry(launchedAtLogin: false) }
        XCTAssertEqual(presentations, 1)
        authorization.showPermissionSetup()
        XCTAssertEqual(presentations, 2)
        let restarted = service()
        restarted.onShowPermissionSetup = { presentations += 1 }
        restarted.checkFirstManualEntry(launchedAtLogin: false)
        XCTAssertEqual(presentations, 3)
        granted = true
        let ready = service()
        ready.onShowPermissionSetup = { presentations += 1 }
        ready.checkFirstManualEntry(launchedAtLogin: false)
        XCTAssertEqual(presentations, 3)
        granted = false
        ready.refreshPermissions()
        XCTAssertEqual(ready.permissionRequirements.first?.status, .notGranted)
        ready.checkFirstManualEntry(launchedAtLogin: false)
        XCTAssertEqual(presentations, 3)
    }

    @MainActor
    func testPermissionRequirementsReflectGrantedPendingAndRepairStates() throws {
        for (accessibility, paste, restarted, expected) in [
            (false, false, false, PermissionRequirement.Status.notGranted),
            (true, true, false, .granted), (true, false, false, .pending), (true, false, true, .repair),
        ] {
            let suite = "PhrasePerch.Tests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if restarted { defaults.set(Bundle.main.bundlePath, forKey: AuthorizationService.restartPendingKey) }
            let authorization = AuthorizationService(store: ConfigurationRepository(storage: StubConfigurationStorage()),
                guide: StubAuthorizationGuide(), environment: AuthorizationEnvironment(snapshot: { (accessibility, paste) }),
                defaults: defaults)
            authorization.refreshPermissions()
            XCTAssertEqual(authorization.permissionRequirements.count, 1)
            let item = try XCTUnwrap(authorization.permissionRequirements.first)
            XCTAssertEqual(item.status, expected)
            XCTAssertEqual(item.needsAttention, expected != .granted)
            XCTAssertEqual(item.actionTitle == nil, expected == .granted)
        }
    }

    func testMixedPermissionListOnlyMarksMissingRequirementsForAction() {
        let requirements = [
            PermissionRequirement(id: "accessibility", title: "辅助功能", purpose: "",
                status: .granted, instructions: "", actionTitle: nil),
            PermissionRequirement(id: "screen", title: "屏幕录制", purpose: "",
                status: .notGranted, instructions: "", actionTitle: "授权"),
            PermissionRequirement(id: "optional", title: "可选能力", purpose: "",
                status: .notRequired, instructions: "", actionTitle: nil),
        ]
        XCTAssertEqual(requirements.filter(\.needsAttention).map(\.id), ["screen"])
        XCTAssertEqual(requirements.compactMap(\.actionTitle), ["授权"])
    }

    @MainActor
    func testPermissionSetupRendersAccessibilityAtSupportedSizes() async throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let authorization = AuthorizationService(store: ConfigurationRepository(storage: StubConfigurationStorage()),
            guide: StubAuthorizationGuide(), environment: AuthorizationEnvironment(snapshot: { (false, false) }),
            defaults: defaults)
        authorization.refreshPermissions()
        let requirements = authorization.permissionRequirements
        for (width, height) in [(460, 430), (880, 560), (960, 620), (1070, 620), (1280, 800)] {
            let root = NSHostingView(rootView: PermissionSetupView(requirements: requirements,
                isRestarting: false, feedback: "", onAction: { _ in }, onClose: {}))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            try savePreview(root, name: "permission-setup-\(width)x\(height).png")
            XCTAssertEqual(root.frame.size, CGSize(width: width, height: height))
            window.close()
        }
    }

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
            XCTAssertFalse(coordinator.permissionSetupError.isEmpty)
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
