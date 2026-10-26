import AppKit
import SwiftUI
import XCTest
@testable import PhrasePerch

final class AttachmentPresentationTests: PresentationTestCase {
    @MainActor
    func testAttachmentEditorAndTitleSettingAtAllWindowSizes() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let source = rootDirectory.appendingPathComponent("轮盘附件示例.txt")
        try Data("PhrasePerch attachment preview".utf8).write(to: source)
        let disk = JSONConfigurationStorage(directory: rootDirectory.appendingPathComponent("store"))
        let file = try await disk.importAttachment(from: source)
        let attachment = Snippet(title: "用于快捷发送的附件示例", content: .attachment(file))
        try await disk.save(AppConfiguration(profiles: [AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.attachment-ui", fallbackBundlePath: nil),
            displayName: "ChatGPT", buttons: [attachment, Snippet(title: "文案示例", text: "测试正文")])]))
        let store = ConfigurationRepository(storage: disk)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        defer { coordinator.stop() }
        coordinator.preferencesViewModel.menuTitleCharacterLimit = 30
        let editor = try XCTUnwrap(coordinator.mainWindowViewModel.selectedEditor)
        editor.select(attachment.id)
        let visible = ProcessInfo.processInfo.environment["PHRASEPERCH_VISIBLE_UI_TESTS"] == "1"
        for size in [CGSize(width: 880, height: 560), CGSize(width: 960, height: 620), CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800)] {
            for page in [MainPage.home, .settings] {
                let root = NSHostingView(rootView: makeMainWindowView(coordinator, page: page))
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = root
                if visible { window.center(); window.makeKeyAndOrderFront(nil) }
                root.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(160))
                try savePreview(root, name: "attachment-\(page == .home ? "editor" : "settings")-\(Int(size.width)).png")
                XCTAssertEqual(root.bounds.size, size)
                window.close()
            }
        }
        let saved = await store.flush()
        XCTAssertTrue(saved)
        let restored = try await disk.load()
        XCTAssertEqual(restored.preferences.menuTitleCharacterLimit, 30)
    }
    @MainActor
    func testNativeVariableWidthNavigationReversesReturnAnimation() async throws {
        try requireVisibleUITests()
        let snippets = (0..<16).map { Snippet(title: $0.isMultiple(of: 2) ? "短标题 \($0)" : "向外延伸的单行长标题示例 \($0)", text: "正文") }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.variable-wheel", fallbackBundlePath: nil),
            displayName: "Preview", buttons: snippets)
        let controller = FloatingMenuWindowController()
        controller.titleCharacterLimit = 30
        _ = try unobstructedTestPoint(controller: controller, profile: profile)
        defer { controller.hide() }
        try await Task.sleep(for: .milliseconds(460))
        let rootIDs = controller.pageNodes.map(\.id)
        XCTAssertTrue(controller.hasNextPage)
        controller.enterNextPage()
        try await Task.sleep(for: .milliseconds(155))
        func angle() throws -> CGFloat {
            let view = try XCTUnwrap(controller.panel.contentView as? FloatingMenuView)
            let group = try XCTUnwrap(view.animationLayer?.animation(forKey: "radialMotion") as? CAAnimationGroup)
            let motion = try XCTUnwrap(group.animations?.first as? CAKeyframeAnimation)
            let transform = try XCTUnwrap((motion.values as? [NSValue])?.first).caTransform3DValue
            return atan2(transform.m12, transform.m11)
        }
        XCTAssertEqual(try angle(), 55 * .pi / 180, accuracy: 0.00001)
        try await Task.sleep(for: .milliseconds(440))
        controller.returnToParent()
        try await Task.sleep(for: .milliseconds(155))
        XCTAssertEqual(try angle(), -55 * .pi / 180, accuracy: 0.00001)
        try await Task.sleep(for: .milliseconds(440))
        XCTAssertEqual(controller.pageNodes.map(\.id), rootIDs)
        let view = try XCTUnwrap(controller.panel.contentView as? FloatingMenuView)
        try savePreview(view, name: "attachment-wheel-variable-widths.png")
        controller.hide()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(controller.isPresented)
    }
}
