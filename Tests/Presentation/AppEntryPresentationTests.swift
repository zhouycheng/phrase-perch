import AppKit
import SwiftUI
import XCTest

@testable import PhrasePerch

final class AppEntryPresentationTests: PresentationTestCase {
    @MainActor
    func testStatusButtonOpensDirectlyAndContextMenuKeepsItsActions() throws {
        try requireVisibleUITests()
        let platform = MacAppEntryController()
        defer { platform.stop() }
        var actions: [String] = []
        platform.setMenuBar(visible: true, enabled: true, toggle: { actions.append("toggle") },
            open: { actions.append("open") }, importFile: { actions.append("import") }, exportFile: { actions.append("export") })
        let item = try XCTUnwrap(platform.statusItem)
        let button = try XCTUnwrap(item.button)
        let menu = try XCTUnwrap(platform.statusMenu)
        XCTAssertNil(item.menu)
        button.performClick(nil)
        XCTAssertEqual(actions, ["open"])
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 3)
        menu.performActionForItem(at: 4)
        XCTAssertEqual(actions, ["open", "toggle", "import", "export"])
        platform.refreshMenu(enabled: false)
        XCTAssertEqual(menu.items.first?.state, .off)
    }

    @MainActor
    func testWindowDockAndFocusSurviveMinimizationCloseAndReopen() async throws {
        try requireVisibleUITests()
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initialPolicy = NSApp.activationPolicy()
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store,
            authorizationEnvironment: AuthorizationEnvironment(snapshot: { (true, true) }), defaults: defaults))
        defer { coordinator.stop(); NSApp.setActivationPolicy(initialPolicy) }
        coordinator.openMainWindow(launchedAtLogin: true)
        XCTAssertFalse(coordinator.dependencies.entry.isMainWindowOpen)
        coordinator.openMainWindow()
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "PhrasePerch" && $0.isVisible })
        defer { window.close() }
        for _ in 0..<2 {
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(NSApp.activationPolicy(), .regular)
            XCTAssertTrue(NSApp.isActive)
            XCTAssertTrue(window.isKeyWindow)
            window.miniaturize(nil)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(window.isMiniaturized)
            XCTAssertTrue(coordinator.dependencies.entry.isMainWindowOpen)
            XCTAssertEqual(NSApp.activationPolicy(), .regular)
            coordinator.openMainWindow()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertFalse(window.isMiniaturized)
            XCTAssertTrue(window.isKeyWindow)
            NSApp.deactivate()
            XCTAssertEqual(NSApp.activationPolicy(), .regular)
            window.close()
            XCTAssertFalse(coordinator.dependencies.entry.isMainWindowOpen)
            XCTAssertEqual(NSApp.activationPolicy(), .accessory)
            coordinator.openMainWindow()
            XCTAssertTrue(NSApp.windows.first { $0.title == "PhrasePerch" && $0.isVisible } === window)
        }
        coordinator.preferencesViewModel.dockIconVisible = true
        coordinator.preferencesViewModel.menuBarIconVisible = false
        window.close()
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        coordinator.preferencesViewModel.silentLaunchEnabled = false
        coordinator.openMainWindow(launchedAtLogin: true)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(coordinator.dependencies.entry.isMainWindowOpen)
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }

    @MainActor
    func testStartupSettingsAtAllWindowSizes() async throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let platform = StubAppEntryPlatform()
        platform.loginEnabled = true
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store, defaults: defaults, entryPlatform: platform))
        defer { coordinator.stop() }
        let startupSettings = AnyView(HStack(spacing: 0) {
            NavigationRailView(page: .constant(.settings))
            EditorStyle.separator.frame(width: 1)
            ScrollView {
                AppEntryPreferencesCardView(viewModel: coordinator.preferencesViewModel)
                    .frame(maxWidth: 860).padding(26)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EditorStyle.background).preferredColorScheme(.dark))
        for size in [CGSize(width: 880, height: 560), CGSize(width: 960, height: 620),
            CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800)] {
            for (name, view) in [("startup-settings", startupSettings)] {
                let root = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = root
                root.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                try savePreview(root, name: "\(name)-\(Int(size.width)).png")
                XCTAssertEqual(root.bounds.size, size)
                window.close()
            }
        }
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }
}
