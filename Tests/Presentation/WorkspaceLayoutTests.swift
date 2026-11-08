import AppKit
import SwiftUI
import XCTest
@testable import PhrasePerch

@MainActor
final class WorkspaceLayoutTests: PresentationTestCase {
    func testVisibleNativeDividerDragsFromTheExtendedHitArea() async throws {
        try requireVisibleUITests()
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        store.update {
            $0.profiles = [AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.split", fallbackBundlePath: nil),
                displayName: "分栏检查", buttons: [Snippet(title: "检查文案", text: "# 预览\n\n**拖动分栏** 后正文保持排版。")])]
        }
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        defer { coordinator.stop() }
        let root = NSHostingView(rootView: makeMainWindowView(coordinator))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1070, height: 620),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let split = try XCTUnwrap(descendants(root).compactMap { $0 as? WorkspaceSplitView.SplitView }.first)
        func drag(from start: CGPoint, to end: CGPoint) throws {
            func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: split.convert(point, to: nil), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
            }
            NSApp.postEvent(try event(.leftMouseUp, end), atStart: true)
            NSApp.postEvent(try event(.leftMouseDragged, end), atStart: true)
            window.sendEvent(try event(.leftMouseDown, start))
        }
        try drag(from: CGPoint(x: 203, y: 200), to: CGPoint(x: 260, y: 200))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertGreaterThan(split.hosts[0].frame.width, 250)
        XCTAssertEqual(split.hosts[2].frame.width, 317)
        let second = split.hosts[2].frame.minX - 1
        try drag(from: CGPoint(x: second - 2, y: 200), to: CGPoint(x: second - 100, y: 200))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(split.hosts[1].frame.width, 400, accuracy: 1)
        XCTAssertGreaterThanOrEqual(split.hosts[2].frame.width, 317)
        XCTAssertTrue(split.hosts.allSatisfy { !$0.isHidden })
        try await Task.sleep(for: .milliseconds(100))
        try savePreview(root, name: "workspace-visible-dragged.png")
    }

    func testDividerLimitsKeepTheOtherOuterColumnAndPersistWidths() throws {
        let suite = "PhrasePerch.workspace-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let split = WorkspaceSplitView.SplitView(defaults: defaults)
        XCTAssertEqual(split.hosts.map { $0.frame.width }, [200, 482, 317])
        split.setPosition(-500, ofDividerAt: 1)
        XCTAssertEqual(split.hosts.map { $0.frame.width }, [200, 400, 399])
        split.setPosition(5000, ofDividerAt: 0)
        XCTAssertEqual(split.hosts[0].frame.width, 200)
        XCTAssertEqual(split.hosts[2].frame.width, 399)
        split.setPosition(5000, ofDividerAt: 1)
        XCTAssertEqual(split.hosts[2].frame.width, 300)
        split.setPosition(5000, ofDividerAt: 0)
        XCTAssertEqual(split.hosts.map { $0.frame.width }, [299, 400, 300])
        let restored = WorkspaceSplitView.SplitView(defaults: defaults)
        XCTAssertEqual(restored.hosts.map { $0.frame.width }, split.hosts.map { $0.frame.width })
        for width in [1280.0, 1440.0] {
            split.setFrameSize(CGSize(width: width - 69, height: 800))
            split.setPosition(-500, ofDividerAt: 1)
            XCTAssertGreaterThanOrEqual(split.hosts[1].frame.width, 400)
            XCTAssertLessThanOrEqual(split.hosts[2].frame.width, 640)
            XCTAssertEqual(split.hosts[0].frame.width, 299)
        }
        split.setFrameSize(CGSize(width: 1001, height: 620))
        XCTAssertEqual(split.hosts.map { $0.frame.width }, [200, 400, 399])
        let effective = split.splitView(split, effectiveRect: CGRect(x: 200, y: 0, width: 1, height: 620),
            forDrawnRect: CGRect(x: 200, y: 0, width: 1, height: 620), ofDividerAt: 0)
        XCTAssertEqual(effective.width, 8)
    }

    func testInvalidSavedWidthsAndSmallWindowRequestsUseSafeLimits() throws {
        let suite = "PhrasePerch.workspace-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(-100, forKey: WorkspaceSplitView.SplitView.sidebarKey)
        defaults.set(2000, forKey: WorkspaceSplitView.SplitView.editorKey)
        let split = WorkspaceSplitView.SplitView(defaults: defaults)
        XCTAssertEqual(split.hosts.map { $0.frame.width }, [200, 400, 399])
        split.setFrameSize(.zero)
        XCTAssertEqual(split.hosts.map { $0.frame.width }, [0, 0, 0])
        XCTAssertEqual(split.hosts.map { $0.frame.minX }, [0, 0, 0])
        split.setFrameSize(CGSize(width: 1001, height: 620))
        XCTAssertEqual(split.hosts.map { $0.frame.width }, [200, 400, 399])
        let columns = EditorColumns(width: 1070, sidebar: .nan, editor: .infinity)
        XCTAssertEqual(columns.sidebar, 200)
        XCTAssertEqual(columns.editor, 317)
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(
            repository: ConfigurationRepository(storage: StubConfigurationStorage())))
        defer { coordinator.stop() }
        let controller = MainWindowController(viewModel: coordinator.mainWindowViewModel, preferences: coordinator.preferencesViewModel)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: EditorColumns.windowSize),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for size in [CGSize(width: 880, height: 560), CGSize(width: 960, height: 620)] {
            let requested = window.frameRect(forContentRect: CGRect(origin: .zero, size: size)).size
            let constrained = controller.windowWillResize(window, to: requested)
            XCTAssertEqual(window.contentRect(forFrameRect: CGRect(origin: .zero, size: constrained)).size, EditorColumns.windowSize)
        }
    }
}
