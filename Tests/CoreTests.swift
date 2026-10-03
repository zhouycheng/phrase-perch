import XCTest
import SwiftUI
import Darwin
@testable import PhrasePerch

final class CoreTests: XCTestCase {
    private func requireVisibleUITests() throws {
        guard ProcessInfo.processInfo.environment["PHRASEPERCH_VISIBLE_UI_TESTS"] == "1" else {
            throw XCTSkip("Visible desktop tests require explicit PHRASEPERCH_VISIBLE_UI_TESTS=1")
        }
    }
    private func previewDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    @MainActor
    func testSettingsWindowIsReusedAfterRepeatedOpenAndClose() throws {
        try requireVisibleUITests()
        let coordinator = AppCoordinator()
        coordinator.openSettings()
        let first = try XCTUnwrap(NSApp.windows.first { $0.title == "PhrasePerch" })
        defer { first.close(); coordinator.stop() }
        XCTAssertTrue(first.titleVisibility == .visible)
        XCTAssertFalse(first.styleMask.contains(.fullSizeContentView))
        coordinator.openSettings()
        XCTAssertEqual(NSApp.windows.filter { $0.title == first.title }.count, 1)
        first.close()
        coordinator.openSettings()
        let reopened = try XCTUnwrap(NSApp.windows.first { $0.title == first.title })
        XCTAssertTrue(reopened === first)
        XCTAssertTrue(reopened.isVisible)
    }
    func testPerApplicationEnableAndExclusiveTriggerChoice() throws {
        var modifierProfile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.modifier", fallbackBundlePath: nil),
            displayName: "Modifier", buttons: [Snippet(title: "文案", text: "正文")])
        var shortcutProfile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.shortcut", fallbackBundlePath: nil),
            displayName: "Shortcut", displayMode: .shortcutOnly, buttons: modifierProfile.buttons)
        shortcutProfile.buttons[0].id = UUID()
        XCTAssertTrue(modifierProfile.canTrigger(.modifier))
        XCTAssertFalse(modifierProfile.canTrigger(.shortcut))
        XCTAssertFalse(shortcutProfile.canTrigger(.modifier))
        XCTAssertTrue(shortcutProfile.canTrigger(.shortcut))
        modifierProfile.isEnabled = false
        XCTAssertFalse(modifierProfile.canTrigger(.modifier))
        XCTAssertFalse(modifierProfile.canTrigger(.shortcut))
        XCTAssertTrue(shortcutProfile.canTrigger(.shortcut))
        modifierProfile.displayMode = .shortcutOnly
        XCTAssertFalse(modifierProfile.canTrigger(.shortcut))
        modifierProfile.isEnabled = true
        XCTAssertTrue(modifierProfile.canTrigger(.shortcut))
        XCTAssertFalse(modifierProfile.canTrigger(.modifier))
        shortcutProfile.buttons[0].isEnabled = false
        XCTAssertFalse(shortcutProfile.canTrigger(.shortcut))
        let configuration = AppConfiguration(profiles: [modifierProfile, shortcutProfile])
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(try JSONDecoder().decode(DisplayMode.self, from: Data("\"modifierClick\"".utf8)), .modifierClick)
    }

    @MainActor
    func testEditorAutoSaveStatusFailureRetryAndBackupRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.isReady)
        var profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.editor", fallbackBundlePath: nil),
                                 displayName: "Editor", buttons: [Snippet(title: "第一条", text: "初始正文")])
        store.configuration.profiles = [profile]
        XCTAssertEqual(store.saveStatus, "正在保存…")
        var saved = await store.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(store.saveStatus, "已保存")
        profile.buttons[0].text = "修改后的正文"
        store.configuration.profiles = [profile]
        for _ in 0..<100 where store.savedRevision != store.revision {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.saveStatus, "已保存")
        let disk = ConfigurationDisk(directory: directory)
        let readback = try await disk.load()
        XCTAssertEqual(readback.profiles[0].buttons[0].text, "修改后的正文")
        profile.buttons[0].title = ""
        store.configuration.profiles = [profile]
        saved = await store.flush()
        XCTAssertFalse(saved)
        XCTAssertEqual(store.saveStatus, "保存失败")
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].text, "修改后的正文")
        profile.buttons[0].title = "修复标题"
        store.configuration.profiles = [profile]
        saved = await store.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(store.saveStatus, "已保存")
        await store.restoreBackup()
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].title, "第一条")
        XCTAssertEqual(store.saveStatus, "已保存")
    }

    func testExclusiveAppLockAndRelease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        let first = try XCTUnwrap(acquireInstanceLock(at: url))
        XCTAssertNil(try acquireInstanceLock(at: url))
        close(first)
        let reopened = try XCTUnwrap(acquireInstanceLock(at: url))
        close(reopened)
        XCTAssertThrowsError(try acquireInstanceLock(at: directory.appendingPathComponent("missing/instance.lock")))
    }
    func testAuthorizationRequiresBothActualPermissions() {
        XCTAssertEqual(InputAuthorizationStatus(accessibility: false, paste: false), .needsAccessibility)
        XCTAssertEqual(InputAuthorizationStatus(accessibility: false, paste: true), .needsAccessibility)
        XCTAssertEqual(InputAuthorizationStatus(accessibility: true, paste: false), .needsPasteAccess)
        XCTAssertEqual(InputAuthorizationStatus(accessibility: true, paste: true), .ready)
    }
    @MainActor
    func testPermissionRowPreviews() throws {
        let states: [(AuthorizationFlow.Step, String)] = [(.authorize, "waiting"), (.restart, "restart"),
                                                          (.reauthorize, "reauthorize"), (.ready, "ready")]
        let docs = try previewDirectory()
        for (step, filename) in states {
            let view = NSHostingView(rootView: PermissionRow(step: step, detail: "读取输入位置与粘贴文案", action: {}).padding(20)
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
    func testHoldQuickReleaseAndLateCheck() throws {
        var session = HoldMenuSession()
        let token = try XCTUnwrap(session.begin(.modifier))
        XCTAssertNil(session.release(.modifier, selection: nil))
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(session.show(token))
        let next = try XCTUnwrap(session.begin(.modifier))
        XCTAssertNotEqual(token, next)
        XCTAssertFalse(session.show(token))
        XCTAssertTrue(session.show(next))
    }
    func testHoldDuplicateEventsAndExactlyOneCommit() throws {
        var session = HoldMenuSession()
        let token = try XCTUnwrap(session.begin(.shortcut))
        XCTAssertNil(session.begin(.shortcut))
        XCTAssertTrue(session.show(token))
        XCTAssertFalse(session.show(token))
        let selection = UUID()
        XCTAssertNil(session.release(.modifier, selection: selection))
        XCTAssertEqual(session.phase, .choosing)
        XCTAssertEqual(session.release(.shortcut, selection: selection), token)
        XCTAssertNil(session.release(.shortcut, selection: selection))
        XCTAssertTrue(session.commit(token))
        XCTAssertFalse(session.commit(token))
        session.cancel()
        XCTAssertFalse(session.commit(token))
    }
    func testHoldNoSelectionAndRetriggerCancelPendingPaste() throws {
        var session = HoldMenuSession()
        let first = try XCTUnwrap(session.begin(.modifier))
        XCTAssertTrue(session.show(first))
        XCTAssertNil(session.release(.modifier, selection: nil))
        XCTAssertEqual(session.phase, .idle)
        let second = try XCTUnwrap(session.begin(.shortcut))
        XCTAssertTrue(session.show(second))
        XCTAssertEqual(session.release(.shortcut, selection: UUID()), second)
        session.cancel()
        let third = try XCTUnwrap(session.begin(.shortcut))
        XCTAssertFalse(session.commit(second))
        XCTAssertTrue(session.isCurrent(third))
    }
    func testMenuClosesOnlyAfterCompleteInsertionOrDispatch() {
        for result in [InsertionResult.insertedVerified, .dispatchedUnverified] { XCTAssertTrue(result.closesMenu) }
        for result in [InsertionResult.notWritten, .unsupported, .partialVerified, .interruptedAfterDispatch, .indeterminate] {
            XCTAssertFalse(result.closesMenu)
        }
    }
    func testCurrentPreferencesRequireExplicitModifier() throws {
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test", fallbackBundlePath: nil),
                                 displayName: "Test", buttons: [Snippet(title: "继续", text: "正文")])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfiguration(profiles: [profile]))) as? [String: Any])
        object["preferences"] = ["isEnabled": false]
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: object)))
        var updated = AppConfiguration(profiles: [profile]); updated.preferences.clickModifier = .shift
        let data = try JSONEncoder().encode(updated)
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: data), updated)
        let preferences = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["preferences"] as? [String: Any])
        XCTAssertNil(preferences["hideAfterInsertion"])
    }
    func testAppEntryVisibilityAlwaysKeepsOneEntry() {
        var visibility = AppEntryVisibility(dock: false, menuBar: false)
        XCTAssertTrue(visibility.menuBar)
        visibility.setMenuBar(false)
        XCTAssertTrue(visibility.menuBar)
        visibility.setDock(true)
        visibility.setMenuBar(false)
        XCTAssertTrue(visibility.dock)
        XCTAssertFalse(visibility.menuBar)
        visibility.setDock(false)
        XCTAssertTrue(visibility.dock)
    }
    func testDockPolicyDoesNotRetryAnAlreadyVisibleDockEntry() {
        XCTAssertFalse(dockPolicyChangeNeeded(currentDockVisible: true, requestedDockVisible: true))
        XCTAssertTrue(dockPolicyChangeNeeded(currentDockVisible: false, requestedDockVisible: true))
        XCTAssertTrue(dockPolicyChangeNeeded(currentDockVisible: true, requestedDockVisible: false))
    }
    func testFloatingButtonTitleMatchesCapsuleTruncation() {
        XCTAssertEqual(floatingButtonTitle("继续"), "继续")
        XCTAssertEqual(floatingButtonTitle("详细解释一下"), "详细解释…")
        XCTAssertEqual(floatingButtonTitle("👩‍💻快速回复"), "👩‍💻快速回…")
    }
    func testCommandQIsRecognizedWithoutOtherModifiers() {
        XCTAssertTrue(isCommandQuitShortcut(charactersIgnoringModifiers: "q", modifiers: .command))
        XCTAssertFalse(isCommandQuitShortcut(charactersIgnoringModifiers: "q", modifiers: [.command, .shift]))
        XCTAssertFalse(isCommandQuitShortcut(charactersIgnoringModifiers: "w", modifiers: .command))
        XCTAssertFalse(isCommandQuitShortcut(charactersIgnoringModifiers: "q", modifiers: []))
    }
    func testRadialGeometryAllItemsAndScreenEdges() throws {
        for visible in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                        CGRect(x: -1440, y: -200, width: 1440, height: 900)] {
            let points = [CGPoint(x: visible.midX, y: visible.midY),
                          CGPoint(x: visible.minX + 1, y: visible.minY + 1),
                          CGPoint(x: visible.maxX - 1, y: visible.minY + 1),
                          CGPoint(x: visible.minX + 1, y: visible.maxY - 1),
                          CGPoint(x: visible.maxX - 1, y: visible.maxY - 1)]
            for count in [1, 3, 6, 12, 24] {
                for point in points {
                    let layout = try XCTUnwrap(RadialLayout(anchor: point, visible: visible, count: count))
                    XCTAssertEqual(layout.items.count, count)
                    XCTAssertEqual(layout.anchor, point)
                    XCTAssertTrue(visible.contains(layout.frame))
                    XCTAssertNil(layout.selectedIndex(at: point))
                    for (index, rect) in layout.items.enumerated() {
                        XCTAssertTrue(visible.contains(rect))
                        XCTAssertEqual(layout.selectedIndex(at: CGPoint(x: rect.midX, y: rect.midY)), index)
                        XCTAssertNil(layout.selectedIndex(at: CGPoint(x: rect.minX, y: rect.minY)))
                        for other in layout.items.dropFirst(index + 1) { XCTAssertFalse(rect.intersects(other)) }
                    }
                }
            }
        }
        XCTAssertNil(RadialLayout(anchor: .zero, visible: CGRect(x: 0, y: 0, width: 100, height: 100), count: 24))
        XCTAssertNil(RadialLayout(anchor: .zero, visible: CGRect(x: 0, y: 0, width: 1440, height: 900), count: 0))
        XCTAssertNil(RadialLayout(anchor: .zero, visible: CGRect(x: 0, y: 0, width: 1440, height: 900), count: 10000))
    }
    func testOldAnimationCannotHideOrEnableNewMenu() {
        var state = MenuPresentation()
        let firstShow = state.show(), oldHide = state.hide(), newShow = state.show()
        XCTAssertFalse(state.finishShow(firstShow))
        XCTAssertFalse(state.finishHide(oldHide))
        XCTAssertTrue(state.presented)
        XCTAssertTrue(state.finishShow(newShow))
        XCTAssertFalse(state.finishShow(newShow))
        let hide = state.hide()
        XCTAssertFalse(state.presented)
        XCTAssertTrue(state.finishHide(hide))
        XCTAssertFalse(state.finishHide(hide))
    }
    @MainActor
    private func unobstructedTestPoint(controller: FloatingPanelController, profile: AppProfile) throws -> CGPoint {
        try requireVisibleUITests()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let visible = screen.visibleFrame
        for point in [CGPoint(x: visible.minX + 200, y: visible.minY + 180),
                      CGPoint(x: visible.maxX - 200, y: visible.minY + 180),
                      CGPoint(x: visible.midX, y: visible.midY)] {
            if controller.show(profile: profile, at: point) { return point }
        }
        throw XCTSkip("Actual foreign overlays occupy every native test area")
    }
    @MainActor
    func testNativeAnimationCancellation() async throws {
        let controller = FloatingPanelController()
        // Isolate animation timing from keyboard activity on the user's live desktop.
        controller.onDismiss = { }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
                                 displayName: "Preview", buttons: [Snippet(title: "继续", text: "正文")])
        let point = try unobstructedTestPoint(controller: controller, profile: profile)
        guard controller.show(profile: profile, at: point) else { throw XCTSkip("An actual foreign overlay occupies the native test area") }
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
        let controller = FloatingPanelController()
        let snippets = [Snippet(title: "继续", text: "正文"), Snippet(title: "检查", text: "正文"),
                        Snippet(title: "解释", text: "正文"), Snippet(title: "隐藏", text: "正文", isEnabled: false)]
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
                                 displayName: "Preview", buttons: snippets)
        XCTAssertTrue(controller.configure(profile: profile, at: CGPoint(x: 500, y: 400),
                                            visible: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        XCTAssertFalse(controller.panel.canBecomeKey)
        XCTAssertFalse(controller.panel.canBecomeMain)
        let layout = try XCTUnwrap(controller.layout)
        XCTAssertEqual(layout.items.count, 3)
        XCTAssertFalse(controller.isInteractive(layout.localAnchor))
        let root = try XCTUnwrap(controller.panel.contentView)
        for index in 0..<3 {
            let rect = layout.itemRect(index: index)
            XCTAssertTrue(root.hitTest(CGPoint(x: rect.midX, y: rect.midY)) is RadialButton)
            let button = try XCTUnwrap(root.subviews[index] as? RadialButton)
            XCTAssertNil(button.action, "Click must never dispatch a paste")
        }
        try savePreview(root, name: "radial-normal.png")
        (root.subviews.first as? RadialButton)?.selected = true
        try savePreview(root, name: "radial-hover.png")
        let many = AppProfile(application: profile.application, displayName: "Preview",
                              buttons: (1...24).map { Snippet(title: "文案\($0)", text: "正文") })
        XCTAssertTrue(controller.configure(profile: many, at: CGPoint(x: -1439, y: -199),
                                            visible: CGRect(x: -1440, y: -200, width: 1440, height: 900)))
        try savePreview(try XCTUnwrap(controller.panel.contentView), name: "radial-edge-24.png")
    }
    @MainActor
    private func savePreview(_ root: NSView, name: String) throws {
        root.layoutSubtreeIfNeeded()
        root.needsDisplay = true
        root.subviews.forEach { $0.needsDisplay = true }
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: previewDirectory().appendingPathComponent(name))
    }
    @MainActor
    func testClipboardRoundTripAndExactText() throws {
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.editor", fallbackBundlePath: nil),
                                 displayName: "Test")
        let data = try JSONEncoder().encode(AppConfiguration(profiles: [profile]))
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: data).profiles[0], profile)
        let board = NSPasteboard(name: NSPasteboard.Name("FloatingInputBar-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("old", forType: .string)
        let text = "  中文 👩🏽‍💻 e\u{301}\n\n末尾\t\n"
        let revision = try copySnippetToClipboard(text, pasteboard: board)
        XCTAssertEqual(board.string(forType: .string), text)
        XCTAssertEqual(board.changeCount, revision)
        board.clearContents()
        XCTAssertNotEqual(board.changeCount, revision, "A changed clipboard must prevent automated paste")
    }
    func testPasteEventsAreCommandVWithoutReturn() throws {
        let (down, up) = try XCTUnwrap(pasteKeyEvents())
        XCTAssertEqual(down.type, .keyDown)
        XCTAssertEqual(up.type, .keyUp)
        for event in [down, up] {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 9)
            XCTAssertEqual(event.flags, .maskCommand)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), clipboardPasteEventTag)
        }
    }
    func testOverlayCoexistenceAndModifierRelease() {
        let menu = CGRect(x: -500, y: 200, width: 324, height: 324)
        let peer = VisibleOverlay(ownerPID: 2, layer: 3, frame: menu, alpha: 1)
        XCTAssertTrue(hasForeignOverlay([peer], ownPID: 1, menuFrame: menu))
        XCTAssertFalse(hasForeignOverlay([peer], ownPID: 2, menuFrame: menu))
        XCTAssertFalse(hasForeignOverlay([peer], ownPID: 1, targetPID: 2, menuFrame: menu))
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let desktopHelper = VisibleOverlay(ownerPID: 3, layer: 25, frame: screen, alpha: 1)
        XCTAssertFalse(hasForeignOverlay([desktopHelper], ownPID: 1, menuFrame: menu, screens: [screen]))
        XCTAssertTrue(hasForeignOverlay([peer], ownPID: 1, menuFrame: menu, screens: [screen]))
        for window in [VisibleOverlay(ownerPID: 2, layer: 0, frame: menu, alpha: 1),
                       VisibleOverlay(ownerPID: 2, layer: 3, frame: menu, alpha: 0),
                       VisibleOverlay(ownerPID: 2, layer: 3, frame: CGRect(x: 900, y: 900, width: 300, height: 300), alpha: 1)] {
            XCTAssertFalse(hasForeignOverlay([window], ownPID: 1, menuFrame: menu))
        }
    }
    func testOrdinaryEditorWithMissingEnabledAttribute() {
        XCTAssertTrue(isOrdinaryTextInput(role: "AXTextArea", subrole: nil, enabled: nil))
        XCTAssertFalse(isOrdinaryTextInput(role: "AXTextArea", subrole: nil, enabled: false))
        XCTAssertFalse(isOrdinaryTextInput(role: "AXTextField", subrole: "AXSecureTextField", enabled: true))
        XCTAssertFalse(isOrdinaryTextInput(role: "AXGroup", subrole: nil, enabled: true))
        XCTAssertFalse(isOrdinaryTextInput(role: nil, subrole: nil, enabled: nil))
    }
    func testApplicationIdentity() {
        XCTAssertEqual(ApplicationIdentity(bundleIdentifier: "com.example.editor", fallbackBundlePath: "/old.app").key,
                       ApplicationIdentity(bundleIdentifier: "com.example.editor", fallbackBundlePath: "/new.app").key)
    }
    func testScreenCoordinateConversion() {
        let point = CGPoint(x: -100, y: 1400)
        XCTAssertEqual(flippedScreenPoint(point, primaryScreenTop: 900), CGPoint(x: -100, y: -500))
        XCTAssertEqual(flippedScreenPoint(flippedScreenPoint(point, primaryScreenTop: 900), primaryScreenTop: 900), point)
    }
    func testVerifiedInsertionEvidence() {
        XCTAssertEqual(verifyInsertion(before: "前选区后", range: NSRange(location: 1, length: 2), text: "中文", after: "前中文后"), .insertedVerified)
        XCTAssertEqual(verifyInsertion(before: "前后", range: NSRange(location: 1, length: 0), text: "中文", after: "前中后"), .partialVerified)
        XCTAssertNil(verifyInsertion(before: "前后", range: NSRange(location: 1, length: 0), text: "中文", after: "前其他后"))
    }
    func testSingleOperationAndLateCompletion() {
        var gate = OperationGate()
        let id = gate.begin()!, generation = gate.generation
        XCTAssertNil(gate.begin())
        gate.markWriting(id)
        XCTAssertTrue(gate.mayHaveMutated)
        gate.invalidate()
        XCTAssertFalse(gate.isCurrent(id, generation: generation))
        XCTAssertNil(gate.begin(), "Cancelled request retains its slot until the worker has returned")
        gate.finish(UUID())
        XCTAssertNil(gate.begin(), "A stale completion must not release another request")
        gate.finish(id)
        XCTAssertNotNil(gate.begin())
        XCTAssertFalse(gate.mayHaveMutated)
    }
    func testValidationDoesNotTrimUserText() throws {
        let snippet = Snippet(title: "正文", text: "  空格\n\n末尾\n")
        try validateSnippet(snippet)
        XCTAssertEqual(snippet.text, "  空格\n\n末尾\n")
        XCTAssertThrowsError(try validateSnippet(Snippet(title: "x", text: "bad\u{0}")))
        XCTAssertThrowsError(try validateSnippet(Snippet(title: "x", text: String(repeating: "中", count: 22000))))
        let identity = ApplicationIdentity(bundleIdentifier: "com.test", fallbackBundlePath: nil)
        let profile = AppProfile(application: identity, displayName: "Test", buttons: [snippet])
        XCTAssertThrowsError(try AppConfiguration(profiles: [profile, profile]).validate())
        XCTAssertThrowsError(try AppConfiguration(schemaVersion: 1).validate())
    }
    func testAtomicStorageAndCorruptRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ConfigurationDisk(directory: directory)
        var config = AppConfiguration()
        try await disk.save(config)
        for _ in 0..<5 {
            config.preferences.isEnabled.toggle()
            try await disk.save(config)
        }
        let loaded = try await disk.load()
        XCTAssertEqual(loaded, config)
        let backups = try await disk.backups()
        XCTAssertEqual(backups.count, 3)
        let file = directory.appendingPathComponent("configuration.json")
        try Data("broken".utf8).write(to: file)
        do { _ = try await disk.load(); XCTFail("Corrupt configuration must not be silently reset") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8))
        let recovered = try await disk.latestBackup()
        try await disk.save(recovered)
        let reloaded = try await disk.load()
        XCTAssertEqual(reloaded, recovered)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix("damaged-") })
    }
    func testInvalidSaveLeavesOldFileUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ConfigurationDisk(directory: directory)
        try await disk.save(AppConfiguration())
        let file = directory.appendingPathComponent("configuration.json")
        let before = try Data(contentsOf: file)
        do { try await disk.save(AppConfiguration(schemaVersion: 999)); XCTFail("Future version must be rejected") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), before)
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let blockedDisk = ConfigurationDisk(directory: blocked)
        do { try await blockedDisk.save(AppConfiguration()); XCTFail("Disk error must propagate") } catch { }
    }
}

private actor StubInputWorker: InputTargetWorker {
    private var captured: (UUID, pid_t)?
    var acceptsCapture = true
    var editable = true
    var focusUnchanged = true
    var selectionUnchanged = true
    var invalidateBeforeDispatch = false
    var preparationDelay: Duration = .zero
    private var readyChecks = 0

    func configure(editable: Bool = true, focusUnchanged: Bool = true, selectionUnchanged: Bool = true,
                   invalidateBeforeDispatch: Bool = false, preparationDelay: Duration = .zero) {
        self.editable = editable; self.focusUnchanged = focusUnchanged; self.selectionUnchanged = selectionUnchanged
        self.invalidateBeforeDispatch = invalidateBeforeDispatch; self.preparationDelay = preparationDelay
    }
    private(set) var lastMode: MenuAnchorMode?
    func captureTarget(id: UUID, pid: pid_t, position: CGPoint, mode: MenuAnchorMode) -> CapturedInputTarget? {
        guard acceptsCapture else { return nil }
        lastMode = mode
        captured = (id, pid); readyChecks = 0
        return CapturedInputTarget(id: id, caretBounds: mode == .caret ? CGRect(x: 50, y: 100, width: 0, height: 20) : nil)
    }
    func prepareCaptured(pid: pid_t, operationID: UUID) async throws -> PreparedInput {
        if preparationDelay != .zero { try await Task.sleep(for: preparationDelay) }
        guard captured?.0 == operationID, captured?.1 == pid, editable, focusUnchanged, selectionUnchanged else {
            throw InputFailure("输入框或选区已变化")
        }
        return PreparedInput(before: nil, selection: NSRange(location: 0, length: 0))
    }
    func readyToPaste(_ id: UUID) -> Bool {
        readyChecks += 1
        return captured?.0 == id && editable && focusUnchanged && selectionUnchanged &&
            (!invalidateBeforeDispatch || readyChecks < 2)
    }
    func readback(_ id: UUID) -> String? { nil }
    func release(_ id: UUID) { if captured?.0 == id { captured = nil } }
}

@MainActor
private final class StubPasteSystem {
    var isCurrent = true
    var released = true
    var authorized = true
    var clipboardChanged = false
    var canDispatch = true
    var copies: [String] = []
    var dispatches = 0
    var revision = 0
    var environment: PasteEnvironment {
        PasteEnvironment(targetIsCurrent: { _ in self.isCurrent }, modifiersReleased: { self.released },
                         authorized: { self.authorized }, copy: { text in
                             self.copies.append(text); self.revision += 1; return self.revision
                         }, clipboardRevision: { self.revision + (self.clipboardChanged ? 1 : 0) },
                         dispatch: {
                             guard self.canDispatch else { return false }
                             self.dispatches += 1; return true
                         })
    }
}

extension CoreTests {
    @MainActor
    func testCapturedTargetCannotBeReplacedAtReleaseOrUsedTwice() async {
        let worker = StubInputWorker(), system = StubPasteSystem()
        let service = TextInsertionService(worker: worker, environment: system.environment)
        let original = UUID(), replacement = UUID()
        let target = NSRunningApplication.current
        let snippet = Snippet(title: "测试", text: "  中文 👩🏽‍💻\n末尾\t\n")
        let captured = await service.captureTarget(id: original, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        XCTAssertNotNil(captured)
        let wrong = await service.insert(snippet, target: target, sessionID: replacement)
        XCTAssertEqual(wrong, .notWritten)
        XCTAssertTrue(system.copies.isEmpty)
        XCTAssertEqual(system.dispatches, 0)
        let result = await service.insert(snippet, target: target, sessionID: original)
        XCTAssertEqual(result, .dispatchedUnverified)
        XCTAssertEqual(system.copies, [snippet.text])
        XCTAssertEqual(system.dispatches, 1)
        let repeated = await service.insert(snippet, target: target, sessionID: original)
        XCTAssertEqual(repeated, .notWritten)
        XCTAssertEqual(system.dispatches, 1)
        XCTAssertEqual(system.copies.count, 1)
    }
    @MainActor
    func testCapturedInputChangesPreventClipboardAndPaste() async {
        for failure in ["application", "editor", "selection", "readonly", "permission", "modifier"] {
            let worker = StubInputWorker(), system = StubPasteSystem()
            let service = TextInsertionService(worker: worker, environment: system.environment)
            let token = UUID(), target = NSRunningApplication.current
            _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
            switch failure {
            case "application": system.isCurrent = false
            case "editor": await worker.configure(focusUnchanged: false)
            case "selection": await worker.configure(selectionUnchanged: false)
            case "readonly": await worker.configure(editable: false)
            case "permission": system.authorized = false
            default: system.released = false
            }
            let result = await service.insert(Snippet(title: "测试", text: "正文"), target: target, sessionID: token)
            XCTAssertEqual(result, .notWritten, failure)
            XCTAssertTrue(system.copies.isEmpty, failure)
            XCTAssertEqual(system.dispatches, 0, failure)
        }
    }
    @MainActor
    func testClipboardChangeAndFinalFocusCheckPreventDispatch() async {
        for changedClipboard in [false, true] {
            let worker = StubInputWorker(), system = StubPasteSystem()
            let service = TextInsertionService(worker: worker, environment: system.environment)
            let token = UUID(), target = NSRunningApplication.current
            _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
            system.clipboardChanged = changedClipboard
            await worker.configure(invalidateBeforeDispatch: !changedClipboard)
            let result = await service.insert(Snippet(title: "测试", text: "正文"), target: target, sessionID: token)
            XCTAssertEqual(result, .notWritten)
            XCTAssertEqual(system.copies, ["正文"])
            XCTAssertEqual(system.dispatches, 0)
            XCTAssertTrue(service.message.contains("文案已复制"))
        }
    }
    @MainActor
    func testCancellationDuringPreparationAndConcurrentInsert() async {
        let worker = StubInputWorker(), system = StubPasteSystem()
        let service = TextInsertionService(worker: worker, environment: system.environment)
        let token = UUID(), target = NSRunningApplication.current
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        await worker.configure(preparationDelay: .milliseconds(80))
        let snippet = Snippet(title: "测试", text: "正文")
        let first = Task { await service.insert(snippet, target: target, sessionID: token) }
        while !service.isBusy { await Task.yield() }
        let duplicate = await service.insert(snippet, target: target, sessionID: token)
        XCTAssertEqual(duplicate, .notWritten)
        service.cancel()
        let cancelled = await first.value
        XCTAssertEqual(cancelled, .notWritten)
        XCTAssertTrue(system.copies.isEmpty)
        XCTAssertEqual(system.dispatches, 0)
        XCTAssertFalse(service.isBusy)
    }
    @MainActor
    func testFailedEventCreationDoesNotClaimDispatch() async {
        let worker = StubInputWorker(), system = StubPasteSystem()
        system.canDispatch = false
        let service = TextInsertionService(worker: worker, environment: system.environment)
        let token = UUID(), target = NSRunningApplication.current
        _ = await service.captureTarget(id: token, pid: target.processIdentifier, mouse: .zero, primaryScreenTop: 900)
        let result = await service.insert(Snippet(title: "测试", text: "正文"), target: target, sessionID: token)
        XCTAssertEqual(result, .notWritten)
        XCTAssertEqual(system.dispatches, 0)
    }
    @MainActor
    func testModifierReleaseWaitTimeoutAndNewHoldInvalidation() async {
        XCTAssertEqual(HoldMenuSession.modifierReleaseTimeout, .milliseconds(500))
        var session = HoldMenuSession()
        let token = session.begin(.shortcut)!
        _ = session.show(token); _ = session.release(.shortcut, selection: UUID())
        let timeout = await waitForModifierRelease(timeout: .milliseconds(20), released: { false }, current: { session.isCurrent(token) })
        XCTAssertFalse(timeout)
        let pending = Task {
            await waitForModifierRelease(released: { false }, current: { session.isCurrent(token) })
        }
        await Task.yield()
        session.cancel(); _ = session.begin(.modifier)
        let cancelled = await pending.value
        XCTAssertFalse(cancelled)
        XCTAssertFalse(session.commit(token))
        let immediate = await waitForModifierRelease(released: { true }, current: { true })
        XCTAssertTrue(immediate)
        var released = false
        let releaseTask = Task { try? await Task.sleep(for: .milliseconds(20)); released = true }
        let eventually = await waitForModifierRelease(released: { released }, current: { true })
        await releaseTask.value
        XCTAssertTrue(eventually)
    }
}

extension CoreTests {
    @MainActor
    func testTwentyNativeMenuHoldSelectionsDispatchExactlyOnce() async throws {
        let controller = FloatingPanelController()
        controller.onDismiss = { }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
                                 displayName: "Preview", buttons: [Snippet(title: "继续", text: "继续正文"),
                                                                  Snippet(title: "检查", text: "检查正文"),
                                                                  Snippet(title: "解释", text: "解释正文")])
        let point = try unobstructedTestPoint(controller: controller, profile: profile)
        defer { controller.hide() }
        let worker = StubInputWorker(), system = StubPasteSystem()
        let service = TextInsertionService(worker: worker, environment: system.environment)
        let target = NSRunningApplication.current
        var session = HoldMenuSession()
        for iteration in 0..<40 {
            let mode: MenuAnchorMode = iteration < 20 ? .mouse : .caret
            let token = try XCTUnwrap(session.begin(.modifier))
            let captured = await service.captureTarget(id: token, pid: target.processIdentifier,
                                                      mouse: point, primaryScreenTop: 900, mode: mode)
            XCTAssertNotNil(captured)
            XCTAssertTrue(session.show(token))
            XCTAssertTrue(controller.show(profile: profile, at: point, initialMouse: point, requiresMovement: mode == .caret))
            try await Task.sleep(for: .milliseconds(210))
            let layout = try XCTUnwrap(controller.layout)
            let rect = layout.items[iteration % 3]
            let selectedPoint = CGPoint(x: rect.midX, y: rect.midY)
            XCTAssertEqual(controller.updateSelection(at: selectedPoint), profile.buttons[iteration % 3].id)
            XCTAssertNil(controller.updateSelection(at: point), "Moving back to center clears selection")
            let selected = controller.updateSelection(at: selectedPoint)
            XCTAssertEqual(session.release(.modifier, selection: selected), token)
            controller.hide()
            XCTAssertFalse(controller.isPresented)
            XCTAssertNil(controller.selectedID)
            XCTAssertNil(session.release(.modifier, selection: selected))
            XCTAssertTrue(session.commit(token))
            let result = await service.insert(profile.buttons[iteration % 3], target: target, sessionID: token)
            XCTAssertEqual(result, .dispatchedUnverified)
            XCTAssertEqual(system.dispatches, iteration + 1)
            XCTAssertEqual(system.copies.last, profile.buttons[iteration % 3].text)
            session.cancel()
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(controller.panel.isVisible)
        XCTAssertEqual(system.copies.count, 40)
    }
}


extension CoreTests {
    func testAuthorizationSingleActionTransitionsAndRecovery() {
        var flow = AuthorizationFlow()
        flow.refresh(accessibility: false, paste: false)
        XCTAssertEqual(flow.step, .authorize)
        flow.refresh(accessibility: true, paste: true)
        XCTAssertEqual(flow.step, .restart, "A newly enabled grant requires one restart")
        flow.refresh(accessibility: true, paste: true)
        XCTAssertEqual(flow.step, .restart)
        var restarted = AuthorizationFlow(afterRestart: true)
        restarted.refresh(accessibility: true, paste: false)
        XCTAssertEqual(restarted.step, .reauthorize)
        restarted.refresh(accessibility: true, paste: true)
        XCTAssertEqual(restarted.step, .ready)
        restarted.refresh(accessibility: false, paste: true)
        XCTAssertEqual(restarted.step, .authorize)
        restarted.refresh(accessibility: true, paste: false)
        XCTAssertEqual(restarted.step, .restart)
    }
    func testLegacyAnchorPreferenceDefaultsAndRoundTrips() throws {
        let legacy = Data(#"{"isEnabled":true,"clickModifier":"option"}"#.utf8)
        var preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(preferences.menuAnchorMode, .mouse)
        preferences.menuAnchorMode = .caret
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)), preferences)
        XCTAssertThrowsError(try JSONDecoder().decode(Preferences.self,
            from: Data(#"{"isEnabled":true,"clickModifier":"option","menuAnchorMode":"unknown"}"#.utf8)))
    }
    func testCaretAnchorAndInvalidCoordinateFallback() {
        let screens = [CGRect(x: -1440, y: -200, width: 1440, height: 900), CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let mouse = CGPoint(x: 300, y: 200)
        let bounds = CGRect(x: -100, y: 300, width: 0, height: 20)
        let caret = MenuAnchor(mode: .caret, mouse: mouse, caretBounds: bounds, primaryScreenTop: 900, screens: screens)
        XCTAssertEqual(caret.point, CGPoint(x: -100, y: 590))
        XCTAssertFalse(caret.usedMouseFallback)
        for rect: CGRect? in [nil, .zero, CGRect(x: CGFloat.infinity, y: 0, width: 0, height: 20),
                             CGRect(x: 2000, y: 0, width: 0, height: 20)] {
            let fallback = MenuAnchor(mode: .caret, mouse: mouse, caretBounds: rect, primaryScreenTop: 900, screens: screens)
            XCTAssertEqual(fallback.point, mouse); XCTAssertTrue(fallback.usedMouseFallback)
        }
        XCTAssertEqual(MenuAnchor(mode: .mouse, mouse: mouse, caretBounds: bounds,
                                  primaryScreenTop: 900, screens: screens).point, mouse)
    }
    func testCaretSelectionRequiresActualMouseMovement() {
        var movement = SelectionMovement(initialMouse: CGPoint(x: 100, y: 100), requiresMovement: true)
        XCTAssertFalse(movement.update(CGPoint(x: 100, y: 100)))
        XCTAssertFalse(movement.update(CGPoint(x: 103, y: 100)))
        XCTAssertTrue(movement.update(CGPoint(x: 104, y: 100)))
        XCTAssertTrue(movement.update(CGPoint(x: 100, y: 100)))
    }
    func testEdgeTranslationPreservesRingGeometry() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for count in [1, 3, 6, 12, 24] {
            let middle = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 720, y: 450), visible: screen, count: count))
            let edge = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 1, y: 1), visible: screen, count: count))
            for (a, b) in zip(middle.items, edge.items) {
                XCTAssertEqual(a.midX - middle.center.x, b.midX - edge.center.x, accuracy: 0.001)
                XCTAssertEqual(a.midY - middle.center.y, b.midY - edge.center.y, accuracy: 0.001)
            }
            for ringStart in stride(from: 0, to: min(count, 6), by: 1) {
                let rect = middle.items[ringStart]
                XCTAssertEqual(hypot(rect.midX - middle.center.x, rect.midY - middle.center.y), 100, accuracy: 0.001)
            }
        }
    }
    @MainActor
    func testCaptureModeAndTargetSnapshotPassThrough() async throws {
        let worker = StubInputWorker()
        let service = TextInsertionService(worker: worker, environment: StubPasteSystem().environment)
        for mode in MenuAnchorMode.allCases {
            let token = UUID()
            let result = await service.captureTarget(id: token, pid: getpid(),
                mouse: CGPoint(x: 500, y: 500), primaryScreenTop: 900, mode: mode)
            let captured = try XCTUnwrap(result)
            XCTAssertEqual(captured.id, token)
            XCTAssertEqual(captured.caretBounds != nil, mode == .caret)
            let recordedMode = await worker.lastMode
            XCTAssertEqual(recordedMode, mode)
        }
    }
    @MainActor
    func testRestartFailureKeepsSingleActionAndClearsMarker() async throws {
        for saveSucceeds in [false, true] {
            let suite = "PhrasePerch.Tests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var launches = 0, terminations = 0
            let environment = AuthorizationEnvironment(snapshot: { (true, false) }, save: { _ in saveSucceeds },
                openSettings: { false }, relaunch: { _, _ in launches += 1; throw InputFailure("test launch failure") },
                terminate: { terminations += 1 })
            let coordinator = AppCoordinator(authorization: environment, defaults: defaults)
            defer { coordinator.stop() }
            for _ in 0..<100 where !coordinator.store.isReady { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(coordinator.store.isReady)
            coordinator.refreshPermissions(); coordinator.performAuthorizationAction()
            for _ in 0..<100 where coordinator.isRestarting { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(coordinator.isRestarting)
            XCTAssertEqual(coordinator.authorizationStep, .restart)
            XCTAssertEqual(launches, saveSucceeds ? 1 : 0)
            XCTAssertEqual(terminations, 0)
            XCTAssertNil(defaults.string(forKey: AppCoordinator.restartPendingKey))
            XCTAssertFalse(coordinator.restartExitReady)
        }
    }
    @MainActor
    func testFailedRestartReadbackOffersReauthorizationWithoutOverlay() throws {
        let suite = "PhrasePerch.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Bundle.main.bundlePath, forKey: AppCoordinator.restartPendingKey)
        var opened = 0
        let coordinator = AppCoordinator(authorization: AuthorizationEnvironment(snapshot: { (true, false) },
            openSettings: { opened += 1; return false }), defaults: defaults)
        defer { coordinator.stop() }
        coordinator.refreshPermissions()
        XCTAssertEqual(coordinator.authorizationStep, .reauthorize)
        coordinator.performAuthorizationAction()
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(coordinator.authorizationStep, .reauthorize)
        XCTAssertFalse(NSApp.windows.contains { $0.title == "PhrasePerch — 授权引导" })
        XCTAssertFalse(coordinator.notice.contains("等待"))
    }
}

extension CoreTests {
    @MainActor
    func testSelectionTracksPresentedButtonDuringEntrance() async throws {
        let controller = FloatingPanelController()
        controller.onDismiss = { }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
                                 displayName: "Preview", buttons: [Snippet(title: "继续", text: "正文")])
        let point = try unobstructedTestPoint(controller: controller, profile: profile)
        defer { controller.hide() }
        XCTAssertTrue(controller.show(profile: profile, at: point, initialMouse: point, requiresMovement: true))
        XCTAssertNil(controller.updateSelection(at: point))
        try await Task.sleep(for: .milliseconds(40))
        let button = try XCTUnwrap(controller.panel.contentView?.subviews.first as? RadialButton)
        let layer = try XCTUnwrap(button.layer?.presentation())
        let shown = layer.frame
        let screenPoint = CGPoint(x: controller.panel.frame.minX + shown.midX, y: controller.panel.frame.minY + shown.midY)
        XCTAssertEqual(controller.updateSelection(at: screenPoint), profile.buttons[0].id)
        controller.hide()
        XCTAssertNil(controller.updateSelection(at: screenPoint))
    }
}

extension CoreTests {
    @MainActor
    func testAuthorizationDragCardUsesCurrentApplicationAndNoExtraActions() throws {
        let guide = AuthorizationGuideController()
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
    func testAuthorizationCardFitsNegativeCoordinateDisplay() {
        let visible = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let frame = authorizationGuideFrame(settings: CGRect(x: -900, y: -180, width: 800, height: 800), visible: visible)
        XCTAssertTrue(visible.contains(frame))
    }
}
