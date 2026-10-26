import AppKit
import ApplicationServices
import XCTest
import SwiftUI
@testable import PhrasePerch

final class GroupedMenuTests: PresentationTestCase {
    func profile() -> AppProfile {
        let snippets = (0..<15).map { Snippet(title: "文案 \($0)", text: "正文 👩‍💻\n第二行") }
        let leaf = SnippetGroup(title: "三级", children: snippets.map { MenuNode(kind: .snippet, id: $0.id) })
        let middle = SnippetGroup(title: "二级", children: [MenuNode(kind: .group, id: leaf.id)])
        let top = SnippetGroup(title: "一级", children: [MenuNode(kind: .group, id: middle.id)])
        return AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.groups", fallbackBundlePath: nil),
            displayName: "分组测试", displayMode: .both, buttons: snippets, groups: [top, middle, leaf],
            rootNodes: [MenuNode(kind: .group, id: top.id)])
    }
    func testHierarchyRoundtripAndInvalidReferences() throws {
        let p = profile()
        let config = AppConfiguration(profiles: [p])
        try config.validate()
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(config)), config)
        for kind in ["duplicate", "missing", "cycle", "orphan"] {
            var bad = config
            switch kind {
            case "duplicate": bad.profiles[0].rootNodes.append(p.rootNodes[0])
            case "missing": bad.profiles[0].rootNodes.append(MenuNode(kind: .snippet, id: UUID()))
            case "cycle": bad.profiles[0].groups[2].children.append(p.rootNodes[0])
            default: bad.profiles[0].rootNodes = []
            }
            XCTAssertThrowsError(try bad.validate(), kind)
        }
        var disabled = p
        disabled.groups[1].isEnabled = false
        XCTAssertTrue(disabled.enabledNodes().isEmpty)
    }
    @MainActor
    func testMovingDeletingAndDuplicatingNestedContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let p = profile()
        store.update { $0.profiles = [p] }
        let editing = ProfileEditingService(repository: store)
        editing.moveNode(p.rootNodes[0], in: p.id, to: p.groups[2].id)
        XCTAssertEqual(store.configuration.profiles[0], p)
        editing.removeGroup(p.groups[1].id, in: p.id)
        XCTAssertEqual(store.configuration.profiles[0].groups[0].children, [MenuNode(kind: .group, id: p.groups[2].id)])
        let duplicate = try XCTUnwrap(editing.duplicateSnippet(p.buttons[0].id, in: p.id))
        XCTAssertTrue(store.configuration.profiles[0].children(of: p.groups[2].id).contains(MenuNode(kind: .snippet, id: duplicate)))
        editing.moveNode(MenuNode(kind: .snippet, id: duplicate), in: p.id, to: nil)
        try store.configuration.validate()
        XCTAssertEqual(store.configuration.profiles[0].rootNodes.last?.id, duplicate)
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }
    func testChildLayoutUsesFixedOrientationAndUniformNodesAcrossScreens() throws {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: -1440, y: -300, width: 1440, height: 900), CGRect(x: 0, y: 900, width: 900, height: 1440)] {
            let center = CGPoint(x: screen.midX, y: screen.midY)
            for count in [1, 2, 3, 4, 5, 6, 7, 12, 13, 512] {
                let nodes = (0..<count).map { RadialNode.content(Snippet(title: "文案 \($0)", text: "正文")) }
                let page = try XCTUnwrap(RadialPage(nodes: nodes, anchor: center, visible: screen, hasPrevious: true))
                let layout = page.layout
                XCTAssertEqual(layout.center, center)
                XCTAssertLessThanOrEqual(layout.items.count, 8)
                XCTAssertEqual(page.slots.compactMap { $0 }.filter { $0.action == .previous }.count, 1)
                let radius = layout.items[0].midY - center.y
                for (index, item) in layout.items.enumerated() {
                    XCTAssertEqual(hypot(item.midX - center.x, item.midY - center.y), radius, accuracy: 0.001)
                    XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(item))
                    for other in layout.items.dropFirst(index + 1) {
                        XCTAssertGreaterThanOrEqual(CircularButtonLayout.edgeGap(item, other), 12)
                    }
                }
            }
        }
    }
    @MainActor
    func testThreeLevelNavigationReturnsAndCancelsLateAnimation() throws {
        let scheduler = ManualAnimationScheduler()
        let controller = FloatingMenuWindowController(animator: FloatingMenuAnimator(scheduler: scheduler))
        let p = profile()
        XCTAssertTrue(controller.configure(profile: p, at: CGPoint(x: 700, y: 350), visible: CGRect(x: 0, y: 0, width: 1600, height: 1200)))
        _ = controller.viewModel.beginShow(initialMouse: .zero, requiresMovement: false)
        let root = try XCTUnwrap(controller.viewModel.page)
        for group in p.groups {
            let source = try XCTUnwrap(controller.viewModel.page)
            let item = source.layout.items[try XCTUnwrap(source.slots.firstIndex { $0?.action == .group(group.id) })]
            let index = scheduler.durations.count
            controller.enterGroup(group.id)
            XCTAssertEqual(controller.currentGroup, group.id)
            XCTAssertTrue(controller.viewModel.page?.slots.contains { $0?.action == .previous } == true)
            XCTAssertNil(controller.updateSelection(at: NSEvent.mouseLocation))
            scheduler.finish(index); scheduler.finish(index + 1)
            XCTAssertNil(controller.selectedID)
            let child = try XCTUnwrap(controller.viewModel.page)
            let back = child.layout.items[try XCTUnwrap(child.slots.firstIndex { $0?.action == .previous })]
            let incoming = CGPoint(x: item.midX - source.layout.center.x, y: item.midY - source.layout.center.y)
            let outgoing = CGPoint(x: back.midX - child.layout.center.x, y: back.midY - child.layout.center.y)
            XCTAssertEqual((incoming.x * outgoing.x + incoming.y * outgoing.y)
                / (hypot(incoming.x, incoming.y) * hypot(outgoing.x, outgoing.y)), -1, accuracy: 0.001)
        }
        try savePreview(try XCTUnwrap(controller.panel.contentView), name: "radial-nested-group.png")
        for _ in 0..<3 {
            let current = try XCTUnwrap(controller.viewModel.page)
            let previous = current.layout.items[try XCTUnwrap(current.slots.firstIndex { $0?.action == .previous })]
            let index = scheduler.durations.count
            controller.returnToParent()
            scheduler.finish(index); scheduler.finish(index + 1)
            XCTAssertEqual(controller.layout?.anchor, CGPoint(x: previous.midX, y: previous.midY))
        }
        XCTAssertNil(controller.currentGroup)
        XCTAssertEqual(controller.viewModel.page?.slots, root.slots)
        let displayed = try XCTUnwrap(controller.viewModel.page)
        let index = scheduler.durations.count
        controller.enterGroup(p.groups[0].id)
        controller.hide()
        XCTAssertNil(controller.currentGroup)
        XCTAssertEqual(controller.viewModel.page?.slots, displayed.slots)
        XCTAssertEqual(controller.layout?.anchor, displayed.layout.anchor)
        scheduler.finish(index)
        XCTAssertFalse(controller.isPresented)
    }
    @MainActor
    func testDirectInsertionNeverTouchesClipboardAndWritesOnce() async throws {
        for supported in [true, false] {
            let worker = StubInputWorker(), system = StubPasteSystem()
            let service = ContentInsertionService(worker: worker, environment: system.environment)
            let text = "中文 👩🏽‍💻\n第二行", token = UUID(), target = NSRunningApplication.current
            await worker.setDirectSupported(supported)
            await worker.setReadback(before: "前原文后", selection: NSRange(location: 1, length: 2), readings: ["前\(text)后"])
            _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
            let snippet = Snippet(title: "测试", text: text)
            let result = await service.insert(snippet, target: target, sessionID: token, copyOnInsert: false)
            XCTAssertEqual(result, supported ? .insertedVerified : .notWritten)
            _ = await service.insert(snippet, target: target, sessionID: token, copyOnInsert: false)
            let writes = await worker.directWrites
            XCTAssertEqual(writes, supported ? [text] : [])
            XCTAssertTrue(system.copies.isEmpty)
            XCTAssertEqual(system.dispatches, 0)
        }
    }
    @MainActor
    func testDirectWriteFailureNeverRetriesOrCopies() async throws {
        let worker = StubInputWorker(), system = StubPasteSystem()
        let service = ContentInsertionService(worker: worker, environment: system.environment)
        let token = UUID(), target = NSRunningApplication.current
        await worker.setDirectFailure()
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        let result = await service.insert(Snippet(title: "测试", text: "文案"), target: target, sessionID: token, copyOnInsert: false)
        XCTAssertEqual(result, .indeterminate)
        let writes = await worker.directWrites
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(system.dispatches, 0)
        XCTAssertTrue(system.copies.isEmpty)
    }
    @MainActor
    func testHoverDwellCancelsOnExitAndReturnRestoresRoot() async throws {
        let scheduler = ManualAnimationScheduler()
        let controller = FloatingMenuWindowController(animator: FloatingMenuAnimator(scheduler: scheduler))
        let p = profile()
        XCTAssertTrue(controller.configure(profile: p, at: CGPoint(x: 600, y: 300), visible: CGRect(x: 0, y: 0, width: 1400, height: 1000)))
        _ = controller.viewModel.beginShow(initialMouse: .zero, requiresMovement: false)
        let slot = try XCTUnwrap(controller.layout?.items.first)
        let point = CGPoint(x: slot.midX, y: slot.midY)
        XCTAssertNil(controller.updateSelection(at: point))
        _ = controller.updateSelection(at: .zero)
        try await Task.sleep(for: .milliseconds(210))
        XCTAssertNil(controller.currentGroup)
        _ = controller.updateSelection(at: point)
        let frame = try XCTUnwrap(controller.layout).frame
        XCTAssertTrue(controller.isInteractive(CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)))
        for _ in 0..<100 where scheduler.durations.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(controller.currentGroup, p.groups[0].id)
        XCTAssertEqual(scheduler.durations.count, 1)
        guard scheduler.durations.count == 1 else { return }
        scheduler.finish(0); scheduler.finish(1)
        let content = try XCTUnwrap(controller.viewModel.page)
        let back = content.layout.items[try XCTUnwrap(content.slots.firstIndex { $0?.action == .previous })]
        XCTAssertNil(controller.updateSelection(at: CGPoint(x: back.midX, y: back.midY)))
        for _ in 0..<100 where scheduler.durations.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(scheduler.durations.count, 3)
        guard scheduler.durations.count == 3 else { return }
        scheduler.finish(2); scheduler.finish(3)
        XCTAssertNil(controller.currentGroup)
        XCTAssertNil(controller.selectedID)
        controller.hide()
    }
    @MainActor
    func testGroupEditorRendersAtSupportedSizes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let p = profile()
        store.update { $0.profiles = [p] }
        let model = ProfileEditorViewModel(profileID: p.id, repository: store, editing: ProfileEditingService(repository: store))
        defer { model.stop() }
        for size in [CGSize(width: 880, height: 560), CGSize(width: 960, height: 620), CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800)] {
            model.openGroup(nil)
            let root = NSHostingView(rootView: ProfileEditorView(viewModel: model, editorWidth: 300)
                .background(Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = root
            root.appearance = NSAppearance(named: .darkAqua)
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            try savePreview(root, name: "groups-root-\(Int(size.width)).png")
            for group in p.groups { model.openGroup(group.id) }
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            try savePreview(root, name: "groups-editor-\(Int(size.width)).png")
            XCTAssertEqual(root.bounds.size, size)
            window.close()
        }
    }
    @MainActor
    func testNativeNestedAnimationAndAccessibleNavigation() async throws {
        try requireVisibleUITests()
        let controller = FloatingMenuWindowController()
        controller.interactionMode = .persistent
        let p = profile()
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame
        XCTAssertTrue(controller.show(profile: p, at: CGPoint(x: visible.midX, y: visible.midY)))
        defer { controller.hide() }
        try await Task.sleep(for: .milliseconds(470))
        for group in p.groups {
            let button = try XCTUnwrap((controller.panel.contentView as? FloatingMenuView)?.buttons.compactMap { $0 as? FloatingMenuButton }.first)
            XCTAssertTrue(button.accessibilityPerformPress())
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertEqual(controller.currentGroup, group.id)
            XCTAssertTrue(controller.panel.isVisible)
            XCTAssertNil(controller.selectedID)
        }
        let back = try XCTUnwrap((controller.panel.contentView as? FloatingMenuView)?.buttons.compactMap { $0 as? FloatingMenuButton }.first { $0.title == "← 上一页" })
        XCTAssertTrue(back.accessibilityPerformPress())
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(controller.currentGroup, p.groups[1].id)
        controller.hide()
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertFalse(controller.panel.isVisible)
    }
    func testNoFocusCopiesAndDirectAXCapability() async throws {
        let access = StubAccessibilityAccess()
        access.focusError = .noValue
        let worker = AccessibilityInputWorker(access: access), token = UUID()
        let empty = try await worker.captureTarget(id: token, pid: 4242, position: .zero, mode: .mouse)
        XCTAssertEqual(empty?.focusKind, .nonInput)
        XCTAssertEqual(empty?.canPaste, false)
        access.focusError = .success
        let unchanged = await worker.focusUnchanged(token)
        XCTAssertFalse(unchanged)
        access.writable = true
        let editable = try await worker.captureTarget(id: token, pid: 4242, position: .zero, mode: .mouse)
        XCTAssertEqual(editable?.canDirectWrite, true)
        try await worker.replaceSelection(token, text: "中文")
        XCTAssertEqual(access.writes, 1)
        access.secureInput = true
        do { try await worker.replaceSelection(token, text: "测试"); XCTFail("Secure input") } catch {}
        XCTAssertEqual(access.writes, 1)
    }
}
