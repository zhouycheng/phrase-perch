import XCTest
import SwiftUI
import Darwin
@testable import PhrasePerch

final class CoreTests: XCTestCase {
    @MainActor
    func testSettingsWindowIsReusedAfterRepeatedOpenAndClose() throws {
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
        let states: [(String, String, Bool, String)] = [
            ("辅助功能", "识别当前应用与可编辑输入位置", false, "waiting"),
            ("粘贴输入", "将所选文案粘贴到目标应用", false, "paste"),
            ("辅助功能", "识别当前应用与可编辑输入位置", true, "ready")
        ]
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")
        for (title, detail, isReady, filename) in states {
            let view = NSHostingView(rootView: PermissionRow(title: title, detail: detail,
                isReady: isReady, authorize: {}).padding(20)
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
    func testModifierGestureRequiresContinuousKeyAndEditableSelection() {
        for modifier in ClickModifier.allCases {
            var click = ModifierGesture(modifier: modifier, flags: modifier.mask)
            XCTAssertTrue(click.acceptsEditor(sameEditor: true, selectionLength: 0))
            XCTAssertFalse(click.acceptsEditor(sameEditor: false, selectionLength: 10))
            var selection = click; selection.dragged = true
            XCTAssertTrue(selection.acceptsEditor(sameEditor: true, selectionLength: 10))
            XCTAssertFalse(selection.acceptsEditor(sameEditor: true, selectionLength: 0))
            XCTAssertFalse(selection.acceptsEditor(sameEditor: true, selectionLength: nil))
            selection.observe(flags: 0); selection.observe(flags: modifier.mask)
            XCTAssertFalse(selection.acceptsEditor(sameEditor: true, selectionLength: 10), "Repressing the key cannot resurrect the gesture")
            click.observe(flags: modifier.mask | UInt(CGEventFlags.maskControl.rawValue))
            click.observe(flags: modifier.mask)
            XCTAssertFalse(click.acceptsEditor(sameEditor: true, selectionLength: 0))
            XCTAssertFalse(ModifierGesture(modifier: modifier, flags: 0).valid)
        }
    }
    func testMenuClosesOnlyAfterCompleteInsertionOrDispatch() {
        for result in [InsertionResult.insertedVerified, .dispatchedUnverified] { XCTAssertTrue(result.closesMenu) }
        for result in [InsertionResult.notWritten, .unsupported, .partialVerified, .interruptedAfterDispatch, .indeterminate] {
            XCTAssertFalse(result.closesMenu)
        }
    }
    @MainActor
    func testAuthorizationFileDragPayloadAndSharedPanel() throws {
        let controller = FloatingPanelController(), original = controller.panel
        controller.configureAuthorization(applicationURL: Bundle.main.bundleURL, frame: CGRect(x: 0, y: 0, width: 420, height: 112))
        XCTAssertEqual(controller.content, .authorization)
        XCTAssertFalse(controller.panel.canBecomeKey)
        let root = try XCTUnwrap(controller.panel.contentView)
        let dragRow = try XCTUnwrap(root.subviews.compactMap { $0 as? ApplicationDragView }.first)
        XCTAssertGreaterThan(dragRow.frame.width, 100)
        let blankArea = CGPoint(x: dragRow.frame.maxX - 2, y: dragRow.frame.midY)
        XCTAssertTrue(dragRow.hitTest(blankArea) === dragRow)
        var accepted: [Bool] = []
        dragRow.onDragEnded = { accepted.append($0) }
        dragRow.finishDrag(operation: [])
        dragRow.finishDrag(operation: .copy)
        XCTAssertEqual(accepted, [false, true])
        let item = dragRow.draggingItem()
        XCTAssertEqual(item.item as? NSURL, Bundle.main.bundleURL as NSURL)
        let generalRevision = NSPasteboard.general.changeCount
        let board = NSPasteboard(name: NSPasteboard.Name("PhrasePerch-drag-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects([try XCTUnwrap(item.item as? NSURL)]))
        XCTAssertEqual(board.readObjects(forClasses: [NSURL.self], options: nil)?.first as? NSURL, Bundle.main.bundleURL as NSURL)
        XCTAssertEqual(NSPasteboard.general.changeCount, generalRevision)
        controller.updateAuthorization(status: .needsAccessibility, feedback: "拖入列表后开启开关")
        root.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: docs.appendingPathComponent("Authorization-guide-preview.png"))
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
                                 displayName: "Preview", buttons: [Snippet(title: "继续", text: "正文")])
        controller.configure(profile: profile, at: CGPoint(x: 500, y: 400), visible: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertTrue(controller.panel === original)
        XCTAssertEqual(controller.content, .snippets)
        XCTAssertFalse(controller.panel.contentView?.subviews.contains { $0 is ApplicationDragView } ?? true)
    }
    func testAuthorizationGuidePlacementOnNegativeCoordinateScreens() {
        let visible = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        for settings in [CGRect(x: -900, y: 100, width: 600, height: 500), CGRect(x: -600, y: 0, width: 600, height: 600)] {
            XCTAssertTrue(visible.contains(authorizationGuideFrame(settings: settings, visible: visible)))
        }
        XCTAssertTrue(visible.contains(authorizationGuideFrame(settings: nil, visible: visible)))
        let settings = CGRect(x: -900, y: 100, width: 600, height: 500)
        XCTAssertLessThan(authorizationGuideFrame(settings: settings, visible: visible).maxY, settings.minY)
        let bottom = CGRect(x: -900, y: -180, width: 600, height: 500)
        XCTAssertEqual(authorizationGuideFrame(settings: bottom, visible: visible).minY, bottom.minY + 12)
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
    func testPillGeometryAndPagination() {
        let visible = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        for count in 1...6 {
            for point in [CGPoint(x: -1, y: -199), CGPoint(x: -1439, y: 699), CGPoint(x: -700, y: 100)] {
                let layout = PillLayout(anchor: point, visible: visible, count: count)
                XCTAssertTrue(visible.contains(layout.frame))
                for index in 0..<count {
                    XCTAssertTrue(layout.bar.contains(layout.itemRect(index: index)))
                }
            }
        }
        let point = CGPoint(x: -700, y: 100)
        let above = PillLayout(anchor: point, visible: visible, count: 3)
        XCTAssertFalse(above.below)
        XCTAssertGreaterThan(above.frame.minY, point.y)
        let below = PillLayout(anchor: CGPoint(x: -700, y: 680), visible: visible, count: 3)
        XCTAssertTrue(below.below)
        XCTAssertLessThan(below.frame.maxY, 680)
        let ranges = (0..<3).map { snippetPage(count: 12, page: $0) }
        XCTAssertEqual(ranges, [0..<5, 5..<10, 10..<12])
        XCTAssertEqual(ranges.flatMap { Array($0) }, Array(0..<12))
        XCTAssertEqual(snippetPage(count: 0, page: 0), 0..<0)
        XCTAssertEqual(snippetPage(count: 2, page: 99), 0..<2)
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
    func testAcceptedDropClosesGuideWithoutClaimingAuthorization() async throws {
        let controller = FloatingPanelController()
        controller.showAuthorization(status: .needsAccessibility, feedback: "", applicationURL: Bundle.main.bundleURL)
        try await Task.sleep(for: .milliseconds(220))
        let dragRow = try XCTUnwrap(controller.panel.contentView?.subviews.compactMap { $0 as? ApplicationDragView }.first)
        var accepted: [Bool] = []
        controller.onApplicationDragEnded = { accepted.append($0) }
        dragRow.finishDrag(operation: [])
        XCTAssertTrue(controller.isAuthorization)
        dragRow.finishDrag(operation: .copy)
        XCTAssertFalse(controller.isPresented)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertFalse(controller.panel.isVisible)
        XCTAssertEqual(accepted, [false, true])
    }
    @MainActor
    func testAuthorizationAnimationCannotReplaceNewSnippetMenu() async throws {
        let controller = FloatingPanelController()
        controller.onDismiss = { }
        let panel = controller.panel
        controller.showAuthorization(status: .needsAccessibility, feedback: "拖入后开启开关",
                                     applicationURL: Bundle.main.bundleURL)
        XCTAssertTrue(controller.isAuthorization)
        controller.hide()
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
                                 displayName: "Preview", buttons: [Snippet(title: "继续", text: "正文")])
        let point = try unobstructedTestPoint(controller: controller, profile: profile)
        guard controller.show(profile: profile, at: point) else {
            controller.hide(); throw XCTSkip("An actual foreign overlay occupies the native test area")
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(controller.panel === panel)
        XCTAssertTrue(controller.isPresented)
        XCTAssertFalse(controller.isAuthorization)
        XCTAssertEqual(controller.content, .snippets)
        XCTAssertEqual(controller.panel.alphaValue, 1, accuracy: 0.01)
        controller.hide()
        try await Task.sleep(for: .milliseconds(150))
    }
    @MainActor
    func testNativePillPreviewAndTransparentMargins() throws {
        let controller = FloatingPanelController()
        let snippets = [Snippet(title: "继续", text: "正文"), Snippet(title: "检查", text: "正文"), Snippet(title: "解释", text: "正文")]
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "preview", fallbackBundlePath: nil),
                                 displayName: "Preview", buttons: snippets)
        controller.configure(profile: profile, at: CGPoint(x: 500, y: 400), visible: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertFalse(controller.panel.canBecomeKey)
        XCTAssertFalse(controller.panel.canBecomeMain)
        XCTAssertFalse(controller.isInteractive(CGPoint(x: 100, y: 8)))
        XCTAssertFalse(controller.isInteractive(CGPoint(x: 10, y: 10)))
        XCTAssertTrue(controller.isInteractive(CGPoint(x: 252, y: 44)), "Close remains interactive")
        let root = try XCTUnwrap(controller.panel.contentView)
        let layout = PillLayout(anchor: CGPoint(x: 500, y: 400), visible: CGRect(x: 0, y: 0, width: 1000, height: 800), count: 3)
        for index in 0..<3 {
            let rect = layout.itemRect(index: index)
            XCTAssertTrue(root.hitTest(CGPoint(x: rect.midX, y: rect.midY)) is PillButton)
        }
        root.appearance = NSAppearance(named: .darkAqua)
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")
        try data.write(to: docs.appendingPathComponent("FloatingBar-preview.png"))
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
        let option = ClickModifier.option.mask
        XCTAssertTrue(pressedNewModifier(previous: 0, current: option))
        XCTAssertFalse(pressedNewModifier(previous: option, current: 0))
        XCTAssertFalse(pressedNewModifier(previous: option, current: option))
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
