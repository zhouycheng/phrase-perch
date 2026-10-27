import AppKit
import CoreServices
import XCTest

@testable import PhrasePerch

final class AppEntryServiceTests: XCTestCase {
    @MainActor
    func testOpenCloseAndRepeatedOpenPreserveBackgroundDockPreference() throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let platform = StubAppEntryPlatform()
        let service = AppEntryService(store: ConfigurationRepository(storage: StubConfigurationStorage()),
            platform: platform, defaults: defaults)
        service.start()
        XCTAssertFalse(platform.dockVisible)
        XCTAssertTrue(platform.menuBarVisible)
        service.setMainWindowOpen(true)
        service.setMainWindowOpen(true)
        service.setDockIconVisible(false)
        XCTAssertTrue(platform.dockVisible)
        XCTAssertFalse(service.dockIconVisible)
        XCTAssertEqual(platform.dockRequests, [true])
        service.setMainWindowOpen(false)
        XCTAssertEqual(platform.dockRequests, [true, false])
        XCTAssertFalse(AppEntryPreferencesStorage.load(from: defaults).dock)
        service.setMainWindowOpen(true)
        XCTAssertTrue(platform.dockVisible)
        XCTAssertFalse(service.dockIconVisible)
    }

    @MainActor
    func testEntryProtectionUsesBackgroundPreferenceWhileWindowIsOpen() throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let platform = StubAppEntryPlatform()
        let service = AppEntryService(store: ConfigurationRepository(storage: StubConfigurationStorage()),
            platform: platform, defaults: defaults)
        service.setMainWindowOpen(true)
        service.setMenuBarIconVisible(false)
        XCTAssertTrue(service.menuBarIconVisible)
        service.setDockIconVisible(true)
        service.setMenuBarIconVisible(false)
        service.setDockIconVisible(false)
        service.setMainWindowOpen(false)
        XCTAssertTrue(platform.dockVisible)
        XCTAssertFalse(platform.menuBarVisible)
        XCTAssertEqual(AppEntryPreferencesStorage.load(from: defaults), AppEntryVisibility(dock: true, menuBar: false))
    }

    @MainActor
    func testFailedDockChangesPreservePreferencesAndRecoverWithAnAvailableEntry() throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = AppEntryVisibility(dock: true, menuBar: false)
        AppEntryPreferencesStorage.save(visibility, to: defaults)
        let platform = StubAppEntryPlatform()
        platform.failDockChanges = true
        let service = AppEntryService(store: ConfigurationRepository(storage: StubConfigurationStorage()),
            platform: platform, defaults: defaults)
        service.start()
        XCTAssertTrue(platform.menuBarVisible)
        XCTAssertFalse(service.notice.isEmpty)
        XCTAssertEqual(AppEntryPreferencesStorage.load(from: defaults), visibility)
        platform.failDockChanges = false
        service.setMainWindowOpen(true)
        XCTAssertTrue(platform.dockVisible)
        XCTAssertFalse(platform.menuBarVisible)
        XCTAssertTrue(service.notice.isEmpty)
        service.setMenuBarIconVisible(true)
        service.setDockIconVisible(false)
        platform.failDockChanges = true
        service.setMainWindowOpen(false)
        XCTAssertTrue(platform.dockVisible)
        XCTAssertTrue(platform.menuBarVisible)
        XCTAssertFalse(service.dockIconVisible)
        XCTAssertFalse(service.notice.isEmpty)
        platform.failDockChanges = false
        service.setMainWindowOpen(false)
        XCTAssertFalse(platform.dockVisible)
        XCTAssertTrue(service.notice.isEmpty)
    }

    @MainActor
    func testSilentLaunchDefaultsPersistAndOnlySuppressLoginLaunches() throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        let service = AppEntryService(store: store, platform: StubAppEntryPlatform(), defaults: defaults)
        XCTAssertTrue(service.silentLaunchEnabled)
        XCTAssertFalse(service.shouldOpenMainWindow(launchedAtLogin: true))
        XCTAssertTrue(service.shouldOpenMainWindow(launchedAtLogin: false))
        service.setSilentLaunchEnabled(false)
        let restored = AppEntryService(store: store, platform: StubAppEntryPlatform(), defaults: defaults)
        XCTAssertFalse(restored.silentLaunchEnabled)
        XCTAssertTrue(restored.shouldOpenMainWindow(launchedAtLogin: true))
        XCTAssertTrue(restored.shouldOpenMainWindow(launchedAtLogin: false))
    }

    @MainActor
    func testLoginLaunchRecognitionRequiresTheSystemOpenApplicationMarker() {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertFalse(MacAppEntryController.wasLaunchedAtLogin(nil))
        XCTAssertFalse(MacAppEntryController.wasLaunchedAtLogin(event))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertTrue(MacAppEntryController.wasLaunchedAtLogin(event))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsServiceItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertFalse(MacAppEntryController.wasLaunchedAtLogin(event))
        let reopen = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertFalse(MacAppEntryController.wasLaunchedAtLogin(reopen))
    }

    @MainActor
    func testLoginFailureAndMenuActionsReportActualState() async throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let platform = StubAppEntryPlatform()
        let service = AppEntryService(store: store, platform: platform, defaults: defaults)
        platform.failLoginChanges = true
        service.setLoginEnabled(true)
        XCTAssertFalse(service.loginEnabled)
        XCTAssertTrue(service.notice.contains("登录启动设置失败"))
        platform.failLoginChanges = false
        service.setLoginEnabled(true)
        XCTAssertTrue(service.loginEnabled)
        XCTAssertTrue(service.notice.isEmpty)
        var actions: [String] = []
        service.onOpen = { actions.append("open") }
        service.onImport = { actions.append("import") }
        service.onExport = { actions.append("export") }
        service.start()
        platform.onOpen?(); platform.onImport?(); platform.onExport?(); platform.onToggle?()
        service.refresh()
        XCTAssertEqual(actions, ["open", "import", "export"])
        XCTAssertFalse(platform.menuEnabled)
        service.stop()
        XCTAssertFalse(platform.menuBarVisible)
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }
}
