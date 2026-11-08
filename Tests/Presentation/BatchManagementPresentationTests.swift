import SwiftUI
import XCTest
@testable import PhrasePerch

@MainActor
final class BatchManagementPresentationTests: PresentationTestCase {
    private func fixture(count: Int = 4) async throws -> (ConfigurationRepository, ProfileEditorViewModel, AppProfile) {
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "batch.presentation", fallbackBundlePath: nil),
            displayName: "界面测试", buttons: (0..<count).map { Snippet(title: "快捷内容 \($0)", text: "正文 \($0)") })
        store.update { $0.profiles = [profile] }
        return (store, ProfileEditorViewModel(profileID: profile.id, repository: store,
            editing: ProfileEditingService(repository: store)), profile)
    }

    func testToolbarKeepsItsHeightAndWidthWithSelectionAtAllSizes() async throws {
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        defer { coordinator.stop() }
        for size in [CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800),
            CGSize(width: 1440, height: 900)] {
            let width = EditorColumns(width: size.width).ring
            let toolbar = SnippetToolbarView(displayMode: .both, toggleModifier: {}, toggleShortcut: {},
                addSnippet: {}, addGroup: {}, batchViewModel: model)
                .background(EditorStyle.background).preferredColorScheme(.dark)
            let controller = NSHostingController(rootView: toolbar)
            let probe = controller.view
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 220),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = probe
            model.clearBatchSelection()
            probe.layoutSubtreeIfNeeded()
            try savePreview(probe, name: "batch-toolbar-unselected-\(Int(size.width)).png")
            try await Task.sleep(for: .milliseconds(60))
            let before = controller.sizeThatFits(in: CGSize(width: width, height: 1000))
            XCTAssertGreaterThan(before.height, 50)
            XCTAssertEqual(before.width, width, accuracy: 1)
            model.toggleNodeSelection(profile.buttons[0].id)
            model.toggleNodeSelection(profile.buttons[1].id)
            probe.layoutSubtreeIfNeeded()
            try savePreview(probe, name: "batch-toolbar-\(Int(size.width)).png")
            try await Task.sleep(for: .milliseconds(60))
            let after = controller.sizeThatFits(in: CGSize(width: width, height: 1000))
            XCTAssertEqual(after.width, before.width, accuracy: 1)
            XCTAssertEqual(after.height, before.height, accuracy: 1)
            window.close()
            let editor = try XCTUnwrap(coordinator.mainWindowViewModel.selectedEditor)
            editor.toggleNodeSelection(profile.buttons[0].id)
            editor.toggleNodeSelection(profile.buttons[1].id)
            let root = NSHostingView(rootView: makeMainWindowView(coordinator))
            let main = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            main.isReleasedWhenClosed = false
            main.appearance = NSAppearance(named: .darkAqua)
            main.contentView = root
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            try savePreview(root, name: "batch-management-\(Int(size.width)).png")
            XCTAssertEqual(root.bounds.size, size)
            main.close()
            editor.clearBatchSelection()
        }
    }

    func testDesktopCheckboxRowControlsAndMarqueeRemainIndependent() async throws {
        try requireVisibleUITests()
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        let (window, root) = try await makeListWindow(model)
        defer { window.close() }
        model.select(profile.buttons[1].id)
        try click(window, root, at: CGPoint(x: 36, y: 22))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[0].id])
        try click(window, root, at: CGPoint(x: 300, y: 126))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[0].id, profile.buttons[2].id])
        XCTAssertEqual(model.session.selectedID, profile.buttons[1].id)
        try click(window, root, at: CGPoint(x: 495, y: 22))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(store.configuration.profiles[0].buttons[0].isEnabled)
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[0].id, profile.buttons[2].id])
        try click(window, root, at: CGPoint(x: 554, y: 22))
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(model.deletionID, profile.buttons[0].id)
        XCTAssertEqual(model.session.selectedID, profile.buttons[1].id)
        model.cancelDeletion()
        try await drag(window, root, from: CGPoint(x: 100, y: 280), to: CGPoint(x: 300, y: 70), hold: 0)
        XCTAssertEqual(model.selectedNodeIDs, Set(profile.buttons.suffix(3).map(\.id)))
        try savePreview(root, name: "batch-desktop-selection.png")
        try click(window, root, at: CGPoint(x: 200, y: 280))
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(model.selectedNodeIDs.isEmpty)
    }

    func testToolbarLayoutDistributesEqualButtonWidthsAcrossItsSpace() async throws {
        for (columns, width) in [(2, CGFloat(155)), (2, 216), (4, 400), (4, 600)] {
            let probes = (0..<4).map { _ in NSView() }
            let root = NSHostingView(rootView: ContentToolbarButtonLayout(columns: columns) {
                ForEach(0..<4) { index in
                    ButtonFrameProbe(view: probes[index], idealWidth: CGFloat(30 + index * 8))
                }
            }.frame(width: width))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 100),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            try savePreview(root, name: "batch-equal-width-\(columns)-\(Int(width)).png")
            try await Task.sleep(for: .milliseconds(40))
            let expected = (width - CGFloat(columns - 1) * 6) / CGFloat(columns)
            for view in probes { XCTAssertEqual(view.frame.width, expected, accuracy: 0.5) }
            window.close()
        }
    }

    func testDesktopLongPressReordersSelectionOnlyAfterRelease() async throws {
        try requireVisibleUITests()
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        let (window, root) = try await makeListWindow(model)
        defer { window.close() }
        model.toggleNodeSelection(profile.buttons[0].id)
        model.toggleNodeSelection(profile.buttons[2].id)
        let revision = store.revision
        try await drag(window, root, from: CGPoint(x: 200, y: 22), to: CGPoint(x: 200, y: 205), hold: 0.7)
        XCTAssertEqual(model.nodes.map(\.id), [profile.buttons[1].id, profile.buttons[3].id,
            profile.buttons[0].id, profile.buttons[2].id])
        XCTAssertEqual(store.revision, revision + 1)
        XCTAssertFalse(model.isListGestureActive)
        try savePreview(root, name: "batch-desktop-reordered.png")
    }

    func testDesktopStationaryLongPressLiftsBeforeMovementAndDoesNotActivateOnRelease() async throws {
        try requireVisibleUITests()
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        let (window, root) = try await makeListWindow(model)
        defer { window.close() }
        model.select(profile.buttons[1].id)
        let revision = store.revision
        let point = CGPoint(x: 200, y: 22)
        NSApp.sendEvent(try mouse(.leftMouseDown, window: window, root: root, at: point,
            timestamp: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(for: .milliseconds(680))
        XCTAssertEqual(model.draggingNodeIDs, [profile.buttons[0].id])
        XCTAssertFalse(model.reorderHasMoved)
        XCTAssertEqual(store.revision, revision)
        try await Task.sleep(for: .milliseconds(240))
        try savePreview(root, name: "content-list-floating.png")
        NSApp.sendEvent(try mouse(.leftMouseUp, window: window, root: root, at: point,
            timestamp: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(model.isListGestureActive)
        XCTAssertEqual(model.session.selectedID, profile.buttons[1].id)
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(model.nodes, profile.rootNodes)
        try savePreview(root, name: "content-list-restored.png")
        try click(window, root, at: point)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(model.session.selectedID, profile.buttons[0].id)
    }

    func testDesktopEscapeDuringLiftCancelsWithoutWriting() async throws {
        try requireVisibleUITests()
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        let (window, root) = try await makeListWindow(model)
        defer { window.close() }
        let revision = store.revision
        let start = CGPoint(x: 200, y: 22), end = CGPoint(x: 200, y: 180)
        NSApp.sendEvent(try mouse(.leftMouseDown, window: window, root: root, at: start,
            timestamp: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(for: .milliseconds(680))
        XCTAssertTrue(model.isListGestureActive)
        NSApp.sendEvent(try mouse(.leftMouseDragged, window: window, root: root, at: end,
            timestamp: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(for: .milliseconds(240))
        try savePreview(root, name: "content-list-reorder-preview.png")
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        NSApp.sendEvent(try mouse(.leftMouseUp, window: window, root: root, at: end,
            timestamp: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(model.isListGestureActive)
        XCTAssertTrue(model.selectedNodeIDs.isEmpty)
        XCTAssertEqual(model.nodes, profile.rootNodes)
        XCTAssertEqual(store.revision, revision)
    }

    func testPagedContentListRendersAtSupportedWindowSizes() async throws {
        let (store, model, _) = try await fixture(count: 20)
        defer { model.stop() }
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        defer { coordinator.stop() }
        for size in [CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800),
            CGSize(width: 1440, height: 900)] {
            let root = NSHostingView(rootView: makeMainWindowView(coordinator))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            try savePreview(root, name: "content-pages-\(Int(size.width)).png")
            XCTAssertEqual(coordinator.mainWindowViewModel.selectedEditor?.pagePreview.markers.count, 2)
            XCTAssertEqual(root.bounds.size, size)
            window.close()
        }
    }

    func testDesktopAttachmentGroupAndSyncLiftAndActiveGroupTextKeepsEditing() async throws {
        try requireVisibleUITests()
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        let editing = ProfileEditingService(repository: store)
        editing.editSnippet(profileID: profile.id, snippetID: profile.buttons[0].id) {
            $0.content = .attachment(AttachmentReference(fileName: "附件.png", byteCount: 3))
        }
        model.addGroup()
        let group = try XCTUnwrap(model.profile?.groups.first)
        let source = AppProfile(application: ApplicationIdentity(bundleIdentifier: "mixed.source", fallbackBundlePath: nil),
            displayName: "同步来源", buttons: [Snippet(title: "来源内容", text: "正文")])
        store.update { $0.profiles.append(source) }
        model.addSync(from: source.id)
        let sync = try XCTUnwrap(model.profile?.syncs.first)
        let (window, root) = try await makeListWindow(model)
        defer { window.close() }
        let revision = store.revision, order = model.nodes
        for id in [profile.buttons[0].id, group.id, sync.id] {
            model.clearBatchSelection()
            let rows = ContentListLayout(nodes: model.nodes, markers: model.pagePreview.markers, width: 568)
            let frame = try XCTUnwrap(rows.frames[id])
            let point = CGPoint(x: 30, y: frame.midY)
            NSApp.sendEvent(try mouse(.leftMouseDown, window: window, root: root, at: point,
                timestamp: ProcessInfo.processInfo.systemUptime))
            try await Task.sleep(for: .milliseconds(680))
            XCTAssertEqual(model.draggingNodeIDs, [id])
            NSApp.sendEvent(try mouse(.leftMouseUp, window: window, root: root, at: point,
                timestamp: ProcessInfo.processInfo.systemUptime))
            try await Task.sleep(for: .milliseconds(240))
            XCTAssertEqual(model.nodes, order)
            XCTAssertEqual(store.revision, revision)
        }
        let row = try XCTUnwrap(ContentListLayout(nodes: model.nodes, markers: model.pagePreview.markers, width: 568).frames[group.id])
        let point = CGPoint(x: 200, y: row.midY)
        try click(window, root, at: point)
        try await Task.sleep(for: .milliseconds(80))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        NSApp.sendEvent(try mouse(.leftMouseDown, window: window, root: root, at: point,
            timestamp: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(for: .milliseconds(680))
        XCTAssertFalse(model.isListGestureActive)
        NSApp.sendEvent(try mouse(.leftMouseUp, window: window, root: root, at: point,
            timestamp: ProcessInfo.processInfo.systemUptime))
        editor.selectAll(nil)
        editor.insertText("编辑中的分组", replacementRange: editor.selectedRange())
        XCTAssertEqual(model.groupTitle(group.id), "编辑中的分组")
        try savePreview(root, name: "content-list-mixed.png")
    }

    func testDesktopLosingKeyWindowCancelsPendingAndLiftedPress() async throws {
        try requireVisibleUITests()
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        let (window, root) = try await makeListWindow(model)
        let other = NSWindow(contentRect: CGRect(x: 750, y: 100, width: 200, height: 150),
            styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { window.close(); other.close() }
        let revision = store.revision
        for wait in [100, 680] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(120))
            XCTAssertTrue(window.isKeyWindow)
            let point = CGPoint(x: 200, y: 22)
            NSApp.sendEvent(try mouse(.leftMouseDown, window: window, root: root, at: point,
                timestamp: ProcessInfo.processInfo.systemUptime))
            try await Task.sleep(for: .milliseconds(wait))
            if wait > 600 { XCTAssertTrue(model.isListGestureActive) }
            other.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(680))
            XCTAssertFalse(model.isListGestureActive)
            NSApp.sendEvent(try mouse(.leftMouseUp, window: window, root: root, at: point,
                timestamp: ProcessInfo.processInfo.systemUptime))
            XCTAssertEqual(model.nodes, profile.rootNodes)
            XCTAssertEqual(store.revision, revision)
        }
    }

    func testDesktopMarqueeAutoScrollSelectsBeyondViewport() async throws {
        try requireVisibleUITests()
        let (_, model, profile) = try await fixture(count: 40)
        defer { model.stop() }
        let (window, root) = try await makeListWindow(model)
        defer { window.close() }
        try await drag(window, root, from: CGPoint(x: 100, y: 49), to: CGPoint(x: 300, y: 304), hold: 0, dwell: 0.8)
        XCTAssertGreaterThan(model.selectedNodeIDs.count, 6)
        XCTAssertTrue(model.selectedNodeIDs.contains(profile.buttons[8].id))
    }

    func testDesktopEscapeAndOutsideDropCancelSelectionAndReorder() async throws {
        try requireVisibleUITests()
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        let (window, root) = try await makeListWindow(model)
        defer { window.close() }
        try click(window, root, at: CGPoint(x: 200, y: 280))
        model.toggleNodeSelection(profile.buttons[0].id)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(model.selectedNodeIDs.isEmpty)
        model.toggleNodeSelection(profile.buttons[0].id)
        let before = store.configuration
        try await drag(window, root, from: CGPoint(x: 200, y: 22), to: CGPoint(x: 700, y: 250), hold: 0.7)
        XCTAssertEqual(store.configuration, before)
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[0].id])
        XCTAssertFalse(model.isListGestureActive)
    }

    func testDesktopReorderAutoScrollCommitsOnceBeyondViewport() async throws {
        try requireVisibleUITests()
        let (store, model, profile) = try await fixture(count: 40)
        defer { model.stop() }
        let (window, root) = try await makeListWindow(model)
        defer { window.close() }
        let revision = store.revision
        try await drag(window, root, from: CGPoint(x: 200, y: 22), to: CGPoint(x: 200, y: 304), hold: 0.7, dwell: 0.8)
        let index = try XCTUnwrap(model.nodes.firstIndex { $0.id == profile.buttons[0].id })
        try savePreview(root, name: "batch-reorder-auto-scroll.png")
        XCTAssertGreaterThan(index, 7)
        XCTAssertEqual(store.revision, revision + 1)
        XCTAssertFalse(model.isListGestureActive)
    }

    private func makeListWindow(_ model: ProfileEditorViewModel) async throws -> (NSWindow, NSHostingView<some View>) {
        let root = NSHostingView(rootView: GroupContentsView(viewModel: model)
            .background(EditorStyle.background).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 600, height: 350),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        return (window, root)
    }
    private func mouse(_ type: NSEvent.EventType, window: NSWindow, root: NSView, at point: CGPoint,
        timestamp: TimeInterval, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let local = CGPoint(x: point.x, y: root.isFlipped ? point.y : root.bounds.height - point.y)
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: root.convert(local, to: nil),
            modifierFlags: modifiers, timestamp: timestamp, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
    }
    private func click(_ window: NSWindow, _ root: NSView, at point: CGPoint) throws {
        let now = ProcessInfo.processInfo.systemUptime
        let down = try mouse(.leftMouseDown, window: window, root: root, at: point, timestamp: now)
        let up = try mouse(.leftMouseUp, window: window, root: root, at: point, timestamp: now + 0.02)
        NSApp.postEvent(up, atStart: true)
        NSApp.sendEvent(down)
        NSApp.sendEvent(up)
    }
    private func drag(_ window: NSWindow, _ root: NSView, from start: CGPoint, to end: CGPoint,
        hold: TimeInterval, dwell: TimeInterval = 0.1) async throws {
        NSApp.sendEvent(try mouse(.leftMouseDown, window: window, root: root, at: start,
            timestamp: ProcessInfo.processInfo.systemUptime))
        if hold > 0 { try await Task.sleep(for: .milliseconds(Int(hold * 1000))) }
        for step in 1...8 {
            try await Task.sleep(for: .milliseconds(30))
            let progress = CGFloat(step) / 8
            let point = CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
            NSApp.sendEvent(try mouse(.leftMouseDragged, window: window, root: root, at: point,
                timestamp: ProcessInfo.processInfo.systemUptime))
        }
        try await Task.sleep(for: .milliseconds(Int(dwell * 1000)))
        NSApp.sendEvent(try mouse(.leftMouseUp, window: window, root: root, at: end,
            timestamp: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(for: .milliseconds(100))
    }

    private struct ButtonFrameProbe: NSViewRepresentable {
        let view: NSView
        let idealWidth: CGFloat
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ nsView: NSView, context: Context) {}
        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
            CGSize(width: proposal.width ?? idealWidth, height: 28)
        }
    }
}
