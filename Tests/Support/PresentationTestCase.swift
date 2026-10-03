import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

class PresentationTestCase: XCTestCase {
    func requireVisibleUITests() throws {
        guard ProcessInfo.processInfo.environment["PHRASEPERCH_VISIBLE_UI_TESTS"] == "1" else {
            throw XCTSkip("Visible desktop tests require explicit PHRASEPERCH_VISIBLE_UI_TESTS=1")
        }
    }

    func previewDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    func unobstructedTestPoint(controller: FloatingMenuWindowController, profile: AppProfile) throws -> CGPoint {
        try requireVisibleUITests()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let visible = screen.visibleFrame
        for point in [
            CGPoint(x: visible.minX + 200, y: visible.minY + 180),
            CGPoint(x: visible.maxX - 200, y: visible.minY + 180),
            CGPoint(x: visible.midX, y: visible.midY),
        ] {
            if controller.show(profile: profile, at: point) { return point }
        }
        throw XCTSkip("Actual foreign overlays occupy every native test area")
    }

    @MainActor
    func savePreview(_ root: NSView, name: String) throws {
        root.layoutSubtreeIfNeeded()
        root.needsDisplay = true
        root.subviews.forEach { $0.needsDisplay = true }
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: previewDirectory().appendingPathComponent(name))
    }
}

@MainActor
func makeMainWindowView(_ coordinator: ApplicationCoordinator, page: MainPage = .home) -> MainWindowView {
    coordinator.mainWindowViewModel.page = page
    return MainWindowView(viewModel: coordinator.mainWindowViewModel, preferences: coordinator.preferencesViewModel)
}
