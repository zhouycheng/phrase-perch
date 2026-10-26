import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class NativePresentationTests: PresentationTestCase {
    @MainActor
    func testSnippetRowWhitespaceSelectsAndDeleteRemainsIndependent() async throws {
        try requireVisibleUITests()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let snippets = [Snippet(title: "首条", text: "正文"), Snippet(title: "次条", text: "正文")]
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.hit", fallbackBundlePath: nil),
            displayName: "Test", buttons: snippets)
        store.update { $0.profiles = [profile] }
        let model = ProfileEditorViewModel(profileID: profile.id, repository: store, editing: ProfileEditingService(repository: store))
        defer { model.stop() }
        let root = NSHostingView(rootView: GroupContentsView(viewModel: model).background(EditorStyle.background).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        func click(_ x: CGFloat, _ yFromTop: CGFloat) throws {
            let local = CGPoint(x: x, y: root.isFlipped ? yFromTop : root.bounds.height - yFromTop)
            let location = root.convert(local, to: nil)
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                timestamp: down.timestamp + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
            NSApp.postEvent(up, atStart: true)
            window.sendEvent(down)
            window.sendEvent(up)
        }
        model.select(snippets[1].id)
        try savePreview(root, name: "snippet-row-hit-targets.png")
        try click(300, 22)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.session.selectedID, snippets[0].id)
        model.select(snippets[1].id)
        try click(300, 3)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.session.selectedID, snippets[0].id)
        model.select(snippets[1].id)
        try click(562, 22)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.deletionID, snippets[0].id)
        XCTAssertEqual(model.session.selectedID, snippets[1].id)
        model.cancelDeletion()
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }

    @MainActor
    func testQuickContentHeaderAtAllWindowSizes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let snippet = Snippet(title: "快捷回复", text: "用于界面预览的文案。")
        let child = SnippetGroup(title: "日常回复", children: [MenuNode(kind: .snippet, id: snippet.id)])
        let parent = SnippetGroup(title: "工作", children: [MenuNode(kind: .group, id: child.id)])
        store.update {
            $0.profiles = [AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview.header", fallbackBundlePath: nil),
                displayName: "ChatGPT", displayMode: .both, buttons: [snippet], groups: [parent, child],
                rootNodes: [MenuNode(kind: .group, id: parent.id)])]
        }
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        defer { coordinator.stop() }
        let editor = try XCTUnwrap(coordinator.mainWindowViewModel.selectedEditor)
        for nested in [false, true] {
            editor.openGroup(nil)
            if nested { editor.openGroup(parent.id); editor.openGroup(child.id) }
            for size in [CGSize(width: 880, height: 560), CGSize(width: 960, height: 620), CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800)] {
                let root = NSHostingView(rootView: makeMainWindowView(coordinator))
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = root
                root.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                try savePreview(root, name: "quick-content-\(nested ? "nested" : "root")-\(Int(size.width)).png")
                XCTAssertEqual(root.bounds.size.width, size.width, accuracy: 1)
                XCTAssertEqual(root.bounds.size.height, size.height, accuracy: 1)
                window.close()
            }
        }
    }



    @MainActor
    func testSettingsWindowIsReusedAfterRepeatedOpenAndClose() throws {
        try requireVisibleUITests()
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(
            repository: ConfigurationRepository(storage: StubConfigurationStorage())))
        coordinator.openMainWindow()
        let first = try XCTUnwrap(NSApp.windows.first { $0.title == "PhrasePerch" })
        defer {
            first.close()
            coordinator.stop()
        }
        XCTAssertTrue(first.titleVisibility == .visible)
        XCTAssertFalse(first.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(first.contentView?.bounds.size, CGSize(width: 1070, height: 620))
        XCTAssertEqual(first.contentMinSize, CGSize(width: 880, height: 560))
        coordinator.openMainWindow()
        XCTAssertEqual(NSApp.windows.filter { $0.title == first.title }.count, 1)
        first.close()
        coordinator.openMainWindow()
        let reopened = try XCTUnwrap(NSApp.windows.first { $0.title == first.title })
        XCTAssertTrue(reopened === first)
        XCTAssertTrue(reopened.isVisible)
    }

    @MainActor
    func testNativeEditingMenuSelectionUndoAndSnippetIsolation() async throws {
        try requireVisibleUITests()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let first = Snippet(title: "首条标题", text: "首条正文")
        let second = Snippet(title: "第二标题", text: "第二正文")
        store.update {
            $0.profiles = [
                AppProfile(
                    application: ApplicationIdentity(bundleIdentifier: "test.native", fallbackBundlePath: nil),
                    displayName: "Native", buttons: [first, second])
            ]
        }
        let root = NSHostingView(
            rootView: ProfileEditorView(
                viewModel: ProfileEditorViewModel(
                    profileID: store.configuration.profiles[0].id, repository: store,
                    editing: ProfileEditingService(repository: store),
                    session: SnippetEditorSession(selectedID: first.id)), editorWidth: 280))
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 759, height: 620),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let previousMenu = NSApp.mainMenu
        let previousPolicy = NSApp.activationPolicy()
        defer {
            window.close()
            NSApp.mainMenu = previousMenu
            NSApp.setActivationPolicy(previousPolicy)
        }
        let inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            event.timestamp > 0 && event.window === window ? nil : event
        }
        defer { if let inputMonitor { NSEvent.removeMonitor(inputMonitor) } }
        window.isReleasedWhenClosed = false
        window.contentView = root
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = ApplicationMenuBuilder.make()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func key(_ character: String, shift: Bool = false) throws -> Bool {
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero,
                    modifierFlags: shift ? [.command, .shift] : .command, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil,
                    characters: shift ? character.uppercased() : character,
                    charactersIgnoringModifiers: shift ? character.uppercased() : character, isARepeat: false,
                    keyCode: character == "a" ? 0 : 6))
            return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
        }
        let editor = try XCTUnwrap(descendants(root).compactMap { $0 as? NSTextView }.first { $0.string == first.text })
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertTrue(try key("a"))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (first.text as NSString).length))
        editor.insertText("修改后的正文", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].text, "修改后的正文")
        _ = try key("z")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(editor.string, first.text)
        XCTAssertTrue(try key("z", shift: true))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(editor.string, "修改后的正文")
        root.rootView = ProfileEditorView(
            viewModel: ProfileEditorViewModel(
                profileID: store.configuration.profiles[0].id, repository: store,
                editing: ProfileEditingService(repository: store), session: SnippetEditorSession(selectedID: second.id)),
            editorWidth: 280)
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let secondEditor = try XCTUnwrap(
            descendants(root).compactMap { $0 as? NSTextView }.first { $0.string == second.text })
        XCTAssertTrue(window.makeFirstResponder(secondEditor))
        _ = try key("z")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].text, "修改后的正文")
        XCTAssertEqual(store.configuration.profiles[0].buttons[1].text, second.text)
        let secondTitle = try XCTUnwrap(
            descendants(root).compactMap { $0 as? NSTextField }.first { $0.stringValue == second.title })
        XCTAssertTrue(window.makeFirstResponder(secondTitle))
        let titleEditor = try XCTUnwrap(secondTitle.currentEditor() as? NSTextView)
        titleEditor.insertText(
            "修改第二标题", replacementRange: NSRange(location: 0, length: (second.title as NSString).length))
        try await Task.sleep(for: .milliseconds(50))
        root.rootView = ProfileEditorView(
            viewModel: ProfileEditorViewModel(
                profileID: store.configuration.profiles[0].id, repository: store,
                editing: ProfileEditingService(repository: store), session: SnippetEditorSession(selectedID: first.id)),
            editorWidth: 280)
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let firstTitle = try XCTUnwrap(
            descendants(root).compactMap { $0 as? NSTextField }.first { $0.stringValue == first.title })
        XCTAssertTrue(window.makeFirstResponder(firstTitle))
        _ = try key("z")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].title, first.title)
        XCTAssertEqual(store.configuration.profiles[0].buttons[1].title, "修改第二标题")
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }

    @MainActor
    func testNativeTitleAndBodyClipboardCommandsInBothActivationPolicies() async throws {
        try requireVisibleUITests()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let snippet = Snippet(title: "快捷键标题", text: "快捷键正文\n第二行")
        store.update {
            $0.profiles = [
                AppProfile(
                    application: ApplicationIdentity(bundleIdentifier: "test.clipboard", fallbackBundlePath: nil),
                    displayName: "Native", buttons: [snippet])
            ]
        }
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        let previousMenu = NSApp.mainMenu
        let previousPolicy = NSApp.activationPolicy()
        let pasteboard = NSPasteboard.general
        let originalClipboard = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        var ownedClipboardRevision = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == ownedClipboardRevision {
                pasteboard.clearContents()
                let restored = originalClipboard.map { representations in
                    let item = NSPasteboardItem()
                    for (type, data) in representations { item.setData(data, forType: type) }
                    return item
                }
                if !restored.isEmpty { pasteboard.writeObjects(restored) }
            }
            NSApp.windows.first { $0.title == "PhrasePerch" }?.close()
            coordinator.stop()
            NSApp.mainMenu = previousMenu
            NSApp.setActivationPolicy(previousPolicy)
        }
        NSApp.mainMenu = ApplicationMenuBuilder.make()
        coordinator.openMainWindow()
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "PhrasePerch" })
        let root = try XCTUnwrap(window.contentView)
        let inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            event.timestamp > 0 && event.window === window ? nil : event
        }
        defer { if let inputMonitor { NSEvent.removeMonitor(inputMonitor) } }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func focus(_ string: String) throws -> NSTextView {
            if let view = descendants(root).compactMap({ $0 as? NSTextView }).first(where: { $0.string == string }) {
                XCTAssertTrue(window.makeFirstResponder(view))
                return view
            }
            let field = try XCTUnwrap(
                descendants(root).compactMap { $0 as? NSTextField }.first { $0.stringValue == string })
            XCTAssertTrue(window.makeFirstResponder(field))
            return try XCTUnwrap(field.currentEditor() as? NSTextView)
        }
        func key(_ character: String, shift: Bool = false) throws {
            let codes: [String: UInt16] = ["a": 0, "c": 8, "x": 7, "v": 9, "z": 6]
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero,
                    modifierFlags: shift ? [.command, .shift] : .command, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil,
                    characters: shift ? character.uppercased() : character,
                    charactersIgnoringModifiers: shift ? character.uppercased() : character, isARepeat: false,
                    keyCode: codes[character]!))
            XCTAssertTrue(NSApp.mainMenu?.performKeyEquivalent(with: event) == true)
        }
        for policy in [NSApplication.ActivationPolicy.regular, .accessory] {
            NSApp.setActivationPolicy(policy)
            // AppKit applies the Dock policy asynchronously; open through the app after that transition.
            try await Task.sleep(for: .milliseconds(100))
            coordinator.openMainWindow()
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(NSApp.isActive)
            XCTAssertTrue(window.isKeyWindow)
            for original in [snippet.title, snippet.text] {
                let editor = try focus(original)
                try key("a")
                XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (original as NSString).length))
                try key("c")
                ownedClipboardRevision = pasteboard.changeCount
                XCTAssertEqual(pasteboard.string(forType: .string), original)
                try key("x")
                ownedClipboardRevision = pasteboard.changeCount
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(editor.string, "")
                XCTAssertEqual(store.saveStatus, "待补全")
                XCTAssertNil(store.issue)
                try key("v")
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(editor.string, original)

            }
        }
        let editor = try focus(snippet.text)
        try key("a")
        editor.setMarkedText(
            "zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        editor.insertText("中文输入\n第二行", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].text, "中文输入\n第二行")
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }

    @MainActor
    func testEditorNativeScreenshotsAtThreeWindowSizesAndCounts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.isReady)
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        defer { coordinator.stop() }
        for count in [0, 1, 4, 8, 9, 17] {
            let snippets = (0..<count).map { index in
                Snippet(
                    title: index == 1 ? "这是一条很长的文案标题用于验证完整显示" : "文案\(index + 1)",
                    text: String(repeating: "这是粘贴内容，用于验证正文编辑和滚动。\n", count: 40),
                    isEnabled: index != 2)
            }
            store.update {
                $0.profiles = [
                    AppProfile(
                        application: ApplicationIdentity(bundleIdentifier: "preview.chatgpt", fallbackBundlePath: nil),
                        displayName: "ChatGPT", lastKnownBundlePath: "/Applications/ChatGPT.app", buttons: snippets),
                    AppProfile(
                        application: ApplicationIdentity(bundleIdentifier: "preview.textedit", fallbackBundlePath: nil),
                        displayName: "TextEdit", lastKnownBundlePath: "/System/Applications/TextEdit.app"),
                ]
            }
            for size in [
                CGSize(width: 880, height: 560), CGSize(width: 960, height: 620),
                CGSize(width: 1280, height: 800),
            ] {
                let root = NSHostingView(rootView: makeMainWindowView(coordinator))
                let window = NSWindow(
                    contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                    backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = root
                // Render the native view tree without ordering a window onto the user's desktop.
                root.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                try savePreview(root, name: "editor-\(Int(size.width))-\(count).png")
                XCTAssertEqual(root.bounds.size.width, size.width, accuracy: 1)
                XCTAssertEqual(root.bounds.size.height, size.height, accuracy: 1)
                window.close()
            }
            if count > 8 {
                let profile = store.configuration.profiles[0]
                var selection = SnippetEditorSession()
                selection.select(profile.buttons.last?.id, in: profile.buttons.map(\.id))
                let root = NSHostingView(
                    rootView: ProfileEditorView(
                        viewModel: ProfileEditorViewModel(
                            profileID: profile.id, repository: store, editing: ProfileEditingService(repository: store),
                            session: selection), editorWidth: 300
                    ).background(Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)))
                root.frame = CGRect(x: 0, y: 0, width: 759, height: 620)
                root.appearance = NSAppearance(named: .darkAqua)
                try savePreview(root, name: "editor-last-page-\(count).png")
            }
        }
        for page in [MainPage.settings, .about] {
            for size in [
                CGSize(width: 880, height: 560), CGSize(width: 960, height: 620),
                CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800),
            ] {
                let root = NSHostingView(rootView: makeMainWindowView(coordinator, page: page))
                let window = NSWindow(
                    contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                    backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = root
                root.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                try savePreview(root, name: "page-\(page)-\(Int(size.width)).png")
                XCTAssertEqual(root.bounds.size.width, size.width, accuracy: 1)
                XCTAssertEqual(root.bounds.size.height, size.height, accuracy: 1)
                window.close()
            }
        }
        store.update { $0.profiles = [] }
        let root = NSHostingView(rootView: makeMainWindowView(coordinator))
        root.frame = CGRect(x: 0, y: 0, width: 960, height: 620)
        try savePreview(root, name: "editor-empty-apps.png")
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }

    func testSelectedCapsuleDeletionControlFitsAtEveryNormalWindowSize() {
        for size in [
            CGSize(width: 880, height: 560), CGSize(width: 960, height: 620),
            CGSize(width: 1280, height: 800),
        ] {
            let area = CGSize(width: EditorColumns(width: size.width).ring, height: size.height - 112)
            for width in [CGFloat(88), 160, 210] {
                for count in 1...8 {
                    let layout = EditorRingLayout(size: area, count: count, buttonWidth: width)
                    XCTAssertEqual(layout.items.count, count)
                    let center = CGPoint(x: layout.canvasSize.width / 2, y: layout.canvasSize.height / 2)
                    let radius = layout.items.first.map { hypot($0.midX - center.x, $0.midY - center.y) } ?? 0
                    let deletion = layout.deletionRect
                    XCTAssertTrue(CGRect(origin: .zero, size: layout.canvasSize).contains(deletion))
                    for (index, item) in layout.items.enumerated() {
                        XCTAssertTrue(CGRect(origin: .zero, size: layout.canvasSize).contains(item))
                        XCTAssertEqual(hypot(item.midX - center.x, item.midY - center.y), radius, accuracy: 0.001)
                        XCTAssertFalse(deletion.intersects(item))
                        for (otherIndex, other) in layout.items.enumerated() where index != otherIndex {
                            XCTAssertFalse(item.intersects(other), "Capsules overlap at width \(width), count \(count)")
                            XCTAssertFalse(deletion.intersects(other), "Delete control overlaps at width \(width), count \(count)")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testPermissionRowPreviews() throws {
        let states: [(AuthorizationFlow.Step, String)] = [
            (.authorize, "waiting"), (.restart, "restart"),
            (.reauthorize, "reauthorize"), (.ready, "ready"),
        ]
        let docs = try previewDirectory()
        for (step, filename) in states {
            let view = NSHostingView(
                rootView: PermissionRowView(step: step, detail: "读取输入位置与粘贴文案", action: {}).padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor)))
            view.frame = CGRect(x: 0, y: 0, width: 420, height: 80)
            view.appearance = NSAppearance(named: .darkAqua)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: docs.appendingPathComponent("Authorization-\(filename).png"))
        }
    }

    @MainActor
    func testNativeAnimationCancellation() async throws {
        let controller = FloatingMenuWindowController()
        // Isolate animation timing from keyboard activity on the user's live desktop.
        controller.onDismiss = {}
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
            displayName: "Preview", buttons: [Snippet(title: "继续", text: "正文")])
        let point = try unobstructedTestPoint(controller: controller, profile: profile)
        guard controller.show(profile: profile, at: point) else {
            throw XCTSkip("An actual foreign overlay occupies the native test area")
        }
        controller.hide()
        XCTAssertTrue(controller.show(profile: profile, at: point))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(controller.isPresented)
        XCTAssertTrue(controller.panel.isVisible)
        XCTAssertEqual(controller.panel.alphaValue, 1, accuracy: 0.01)
        controller.hide()
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertFalse(controller.isPresented)
        XCTAssertFalse(controller.panel.isVisible)
    }

    @MainActor
    func testNativeRadialPreviewSelectionAndDisabledSnippets() throws {
        let controller = FloatingMenuWindowController()
        let snippets = [
            Snippet(title: "继续", text: "正文"), Snippet(title: "检查", text: "正文"),
            Snippet(title: "解释", text: "正文"), Snippet(title: "隐藏", text: "正文", isEnabled: false),
        ]
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
            displayName: "Preview", buttons: snippets)
        XCTAssertTrue(
            controller.configure(
                profile: profile, at: CGPoint(x: 500, y: 400),
                visible: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        XCTAssertFalse(controller.panel.canBecomeKey)
        XCTAssertFalse(controller.panel.canBecomeMain)
        let layout = try XCTUnwrap(controller.layout)
        XCTAssertEqual(layout.items.count, 3)
        XCTAssertFalse(controller.isInteractive(layout.localAnchor))
        let root = try XCTUnwrap(controller.panel.contentView as? FloatingMenuView)
        for index in 0..<3 {
            let rect = layout.itemRect(index: index)
            XCTAssertTrue(root.hitTest(CGPoint(x: rect.midX, y: rect.midY)) is FloatingMenuButton)
            let button = try XCTUnwrap(root.buttons[index] as? FloatingMenuButton)
            XCTAssertNil(button.action, "Click must never dispatch a paste")
        }
        try savePreview(root, name: "radial-normal.png")
        (root.buttons.first as? FloatingMenuButton)?.selected = true
        try savePreview(root, name: "radial-hover.png")
        let many = AppProfile(
            application: profile.application, displayName: "Preview",
            buttons: (1...24).map { Snippet(title: "文案\($0)", text: "正文") })
        XCTAssertTrue(
            controller.configure(
                profile: many, at: CGPoint(x: -1439, y: -199),
                visible: CGRect(x: -1440, y: -200, width: 1440, height: 900)))
        try savePreview(try XCTUnwrap(controller.panel.contentView), name: "radial-edge-24.png")
    }

    @MainActor
    func testSelectionTracksPresentedButtonDuringEntrance() async throws {
        // Keep entrance active while the window server installs and removes native event monitors.
        let controller = FloatingMenuWindowController(animator: FloatingMenuAnimator(
            configuration: FloatingMenuAnimationConfiguration(expandDuration: 2), reduceMotion: { false }))
        controller.onDismiss = {}
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
            displayName: "Preview", buttons: [Snippet(title: "继续", text: "正文")])
        let point = try unobstructedTestPoint(controller: controller, profile: profile)
        defer { controller.hide() }
        XCTAssertTrue(controller.show(profile: profile, at: point, initialMouse: point, requiresMovement: true))
        XCTAssertNil(controller.updateSelection(at: point))
        try await Task.sleep(for: .milliseconds(100))
        let view = try XCTUnwrap(controller.panel.contentView as? FloatingMenuView)
        let button = try XCTUnwrap(view.buttons.first)
        let layer = try XCTUnwrap(view.animationLayer?.presentation())
        let shown = layer.convert(CGPoint(x: button.frame.midX, y: button.frame.midY), to: layer.superlayer)
        let screenPoint = CGPoint(
            x: controller.panel.frame.minX + shown.x, y: controller.panel.frame.minY + shown.y)
        XCTAssertEqual(controller.updateSelection(at: screenPoint), profile.buttons[0].id)
        controller.hide()
        XCTAssertNil(controller.updateSelection(at: screenPoint))
        let closing = try XCTUnwrap(view.animationLayer?.animation(forKey: "radialMotion") as? CAAnimationGroup)
        let motion = try XCTUnwrap(closing.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "transform" })
        let from = try XCTUnwrap(motion.fromValue as? NSValue).caTransform3DValue
        XCTAssertGreaterThan(atan2(from.m12, from.m11), 0)
        XCTAssertLessThan(hypot(from.m11, from.m12), 1)
    }

    @MainActor
    func testAuthorizationDragCardUsesCurrentApplicationAndNoExtraActions() throws {
        let guide = AuthorizationGuideWindowController()
        defer { guide.hide() }
        guide.configure(applicationURL: Bundle.main.bundleURL, frame: CGRect(x: 0, y: 0, width: 420, height: 112))
        let root = try XCTUnwrap(guide.panel.contentView)
        let row = try XCTUnwrap(root.subviews.compactMap { $0 as? ApplicationDragView }.first)
        XCTAssertEqual(row.applicationURL, Bundle.main.bundleURL)
        let item = row.draggingItem().item
        XCTAssertEqual((item as? NSURL)?.path, Bundle.main.bundleURL.path)
        XCTAssertTrue(root.hitTest(CGPoint(x: row.frame.maxX - 4, y: row.frame.midY)) === row)
        XCTAssertEqual(root.subviews.compactMap { $0 as? NSButton }.map(\.title), ["×"])
        XCTAssertFalse(guide.panel.canBecomeKey)
        var accepted: [Bool] = []
        guide.onDragEnded = { accepted.append($0) }
        guide.panel.orderFrontRegardless()
        row.finishDrag(operation: [])
        XCTAssertTrue(guide.isVisible)
        row.finishDrag(operation: .copy)
        XCTAssertFalse(guide.isVisible)
        XCTAssertEqual(accepted, [false, true])
        try savePreview(root, name: "authorization-drag-restored.png")
    }
}
