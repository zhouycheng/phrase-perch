import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class DomainRulesTests: PresentationTestCase {
    func testEditorColumnsAndRingFitEverySupportedCount() {
        for size in [
            CGSize(width: 880, height: 560), CGSize(width: 960, height: 620),
            CGSize(width: 1280, height: 800),
        ] {
            let columns = EditorColumns(width: size.width)
            XCTAssertEqual(
                EditorColumns.navigation + columns.sidebar + columns.ring + columns.editor + 3, size.width,
                accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(columns.sidebar, 190)
            XCTAssertGreaterThanOrEqual(columns.editor, 260)
            XCTAssertLessThanOrEqual(columns.editor, 420)
            let area = CGSize(width: columns.ring, height: size.height - 112)
            for count in 1...8 {
                let layout = EditorRingLayout(size: area, count: count)
                XCTAssertEqual(layout.items.count, count)
                XCTAssertEqual(layout.items.first?.midX ?? 0, area.width / 2, accuracy: 0.001)
                let gaps = layout.items.enumerated().map { index, rect in
                    EditorRingLayout.edgeGap(rect, layout.items[(index + 1) % count])
                }
                if count > 2 {
                    XCTAssertLessThan(
                        (gaps.max() ?? 0) - (gaps.min() ?? 0), 0.01,
                        "Unequal visible spacing at \(size), count \(count)")
                }
                for (index, rect) in layout.items.enumerated() {
                    XCTAssertTrue(CGRect(origin: .zero, size: area).contains(rect))
                    for other in layout.items.dropFirst(index + 1) {
                        XCTAssertFalse(
                            rect.insetBy(dx: -3, dy: -3).intersects(other.insetBy(dx: -3, dy: -3)),
                            "Overlap at \(size), count \(count)")
                    }
                }
            }
        }
        let compressed = EditorRingLayout(size: CGSize(width: 408, height: 272), count: 8)
        for (index, rect) in compressed.items.enumerated() {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 408, height: 272).contains(rect))
            XCTAssertFalse(
                compressed.items.dropFirst(index + 1).contains { rect.insetBy(dx: -3, dy: -3).intersects($0) })
        }
        XCTAssertTrue(EditorRingLayout(size: CGSize(width: 458, height: 508), count: 0).items.isEmpty)
        XCTAssertEqual(EditorColumns(width: 1600).editor, 420)
    }

    func testPerApplicationEnableAndExclusiveTriggerChoice() throws {
        var modifierProfile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.modifier", fallbackBundlePath: nil),
            displayName: "Modifier", buttons: [Snippet(title: "文案", text: "正文")])
        var shortcutProfile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.shortcut", fallbackBundlePath: nil),
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

    func testExclusiveAppLockAndRelease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        let first = try XCTUnwrap(SingleInstanceLock.acquire(at: url))
        XCTAssertNil(try SingleInstanceLock.acquire(at: url))
        close(first)
        let reopened = try XCTUnwrap(SingleInstanceLock.acquire(at: url))
        close(reopened)
        XCTAssertThrowsError(
            try SingleInstanceLock.acquire(at: directory.appendingPathComponent("missing/instance.lock")))
    }

    func testAuthorizationRequiresBothActualPermissions() {
        XCTAssertEqual(InputAuthorizationStatus(accessibility: false, paste: false), .needsAccessibility)
        XCTAssertEqual(InputAuthorizationStatus(accessibility: false, paste: true), .needsAccessibility)
        XCTAssertEqual(InputAuthorizationStatus(accessibility: true, paste: false), .needsPasteAccess)
        XCTAssertEqual(InputAuthorizationStatus(accessibility: true, paste: true), .ready)
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
        for result in [
            InsertionResult.notWritten, .unsupported, .partialVerified, .interruptedAfterDispatch, .indeterminate,
        ] {
            XCTAssertFalse(result.closesMenu)
        }
    }

    func testCurrentPreferencesRequireExplicitModifier() throws {
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test", fallbackBundlePath: nil),
            displayName: "Test", buttons: [Snippet(title: "继续", text: "正文")])
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfiguration(profiles: [profile])))
                as? [String: Any])
        object["preferences"] = ["isEnabled": false]
        XCTAssertThrowsError(
            try JSONDecoder().decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: object)))
        var updated = AppConfiguration(profiles: [profile])
        updated.preferences.clickModifier = .shift
        let data = try JSONEncoder().encode(updated)
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: data), updated)
        let preferences = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: data) as? [String: Any])?["preferences"] as? [String: Any])
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

    func testFloatingButtonTitleShowsTenCharactersOnOneLine() {
        XCTAssertEqual(floatingButtonTitle("继续"), "继续")
        XCTAssertEqual(floatingButtonTitle("详细解释一下"), "详细解释一下")
        XCTAssertEqual(floatingButtonTitle("👩‍💻快速回复"), "👩‍💻快速回复")
        XCTAssertEqual(floatingButtonTitle("请检查并解释这段代码"), "请检查并解释这段代码")
        XCTAssertEqual(floatingButtonTitle("请检查并解释这段代码实现"), "请检查并解释这段代码…")
        XCTAssertEqual(floatingButtonTitle("第一行\n第二行"), "第一行 第二行")
        XCTAssertEqual(floatingButtonTitle(String(repeating: "👩‍💻", count: 11)), String(repeating: "👩‍💻", count: 10) + "…")
    }

    func testLegacyTitleSettingsDefaultAndRoundTrip() throws {
        let legacy = Data(#"{"isEnabled":true,"clickModifier":"option"}"#.utf8)
        var preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(preferences.titleAPIBaseURL, Preferences.defaultTitleAPIBaseURL)
        XCTAssertEqual(preferences.titleModel, "")
        preferences.titleAPIBaseURL = "http://localhost:1234/v1"
        preferences.titleModel = "local-model"
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)), preferences)
    }

    func testCommandQIsRecognizedWithoutOtherModifiers() {
        XCTAssertTrue(isCommandQuitShortcut(charactersIgnoringModifiers: "q", modifiers: .command))
        XCTAssertFalse(isCommandQuitShortcut(charactersIgnoringModifiers: "q", modifiers: [.command, .shift]))
        XCTAssertFalse(isCommandQuitShortcut(charactersIgnoringModifiers: "w", modifiers: .command))
        XCTAssertFalse(isCommandQuitShortcut(charactersIgnoringModifiers: "q", modifiers: []))
    }

    @MainActor
    func testClipboardRoundTripAndExactText() throws {
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.editor", fallbackBundlePath: nil),
            displayName: "Test")
        let data = try JSONEncoder().encode(AppConfiguration(profiles: [profile]))
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: data).profiles[0], profile)
        let board = NSPasteboard(name: NSPasteboard.Name("FloatingInputBar-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("old", forType: .string)
        let text = "  中文 👩🏽‍💻 e\u{301}\n\n末尾\t\n"
        let revision = try ClipboardService.copy(text, pasteboard: board)
        XCTAssertEqual(board.string(forType: .string), text)
        XCTAssertEqual(board.changeCount, revision)
        board.clearContents()
        XCTAssertNotEqual(board.changeCount, revision, "A changed clipboard must prevent automated paste")
    }

    func testPasteEventsAreCommandVWithoutReturn() throws {
        let (down, up) = try XCTUnwrap(PasteEventDispatcher.makeEvents())
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
        for window in [
            VisibleOverlay(ownerPID: 2, layer: 0, frame: menu, alpha: 1),
            VisibleOverlay(ownerPID: 2, layer: 3, frame: menu, alpha: 0),
            VisibleOverlay(ownerPID: 2, layer: 3, frame: CGRect(x: 900, y: 900, width: 300, height: 300), alpha: 1),
        ] {
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
        XCTAssertEqual(
            ApplicationIdentity(bundleIdentifier: "com.example.editor", fallbackBundlePath: "/old.app").key,
            ApplicationIdentity(bundleIdentifier: "com.example.editor", fallbackBundlePath: "/new.app").key)
    }

    func testScreenCoordinateConversion() {
        let point = CGPoint(x: -100, y: 1400)
        XCTAssertEqual(flippedScreenPoint(point, primaryScreenTop: 900), CGPoint(x: -100, y: -500))
        XCTAssertEqual(
            flippedScreenPoint(flippedScreenPoint(point, primaryScreenTop: 900), primaryScreenTop: 900), point)
    }

    func testVerifiedInsertionEvidence() {
        XCTAssertEqual(
            verifyInsertion(before: "前选区后", range: NSRange(location: 1, length: 2), text: "中文", after: "前中文后"),
            .insertedVerified)
        XCTAssertEqual(
            verifyInsertion(before: "前后", range: NSRange(location: 1, length: 0), text: "中文", after: "前中后"),
            .partialVerified)
        XCTAssertNil(verifyInsertion(before: "前后", range: NSRange(location: 1, length: 0), text: "中文", after: "前其他后"))
    }

    func testSingleOperationAndLateCompletion() {
        var gate = OperationGate()
        let id = gate.begin()!
        let generation = gate.generation
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
        try SnippetValidator.validate(snippet)
        XCTAssertEqual(snippet.text, "  空格\n\n末尾\n")
        XCTAssertThrowsError(try SnippetValidator.validate(Snippet(title: "x", text: "bad\u{0}")))
        XCTAssertThrowsError(
            try SnippetValidator.validate(Snippet(title: "x", text: String(repeating: "中", count: 22000))))
        let identity = ApplicationIdentity(bundleIdentifier: "com.test", fallbackBundlePath: nil)
        let profile = AppProfile(application: identity, displayName: "Test", buttons: [snippet])
        XCTAssertThrowsError(try AppConfiguration(profiles: [profile, profile]).validate())
        XCTAssertThrowsError(try AppConfiguration(schemaVersion: 1).validate())
    }

    @MainActor
    func testModifierReleaseWaitTimeoutAndNewHoldInvalidation() async {
        XCTAssertEqual(HoldMenuSession.modifierReleaseTimeout, .milliseconds(500))
        var session = HoldMenuSession()
        let token = session.begin(.shortcut)!
        _ = session.show(token)
        _ = session.release(.shortcut, selection: UUID())
        let timeout = await waitForModifierRelease(
            timeout: .milliseconds(20), released: { false }, current: { session.isCurrent(token) })
        XCTAssertFalse(timeout)
        let pending = Task {
            await waitForModifierRelease(released: { false }, current: { session.isCurrent(token) })
        }
        await Task.yield()
        session.cancel()
        _ = session.begin(.modifier)
        let cancelled = await pending.value
        XCTAssertFalse(cancelled)
        XCTAssertFalse(session.commit(token))
        let immediate = await waitForModifierRelease(released: { true }, current: { true })
        XCTAssertTrue(immediate)
        var released = false
        let releaseTask = Task {
            try? await Task.sleep(for: .milliseconds(20))
            released = true
        }
        let eventually = await waitForModifierRelease(released: { released }, current: { true })
        await releaseTask.value
        XCTAssertTrue(eventually)
    }

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
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                Preferences.self,
                from: Data(#"{"isEnabled":true,"clickModifier":"option","menuAnchorMode":"unknown"}"#.utf8)))
    }

    func testCaretAnchorAndInvalidCoordinateFallback() {
        let screens = [
            CGRect(x: -1440, y: -200, width: 1440, height: 900), CGRect(x: 0, y: 0, width: 1440, height: 900),
        ]
        let mouse = CGPoint(x: 300, y: 200)
        let bounds = CGRect(x: -100, y: 300, width: 0, height: 20)
        let caret = MenuAnchor(mode: .caret, mouse: mouse, caretBounds: bounds, primaryScreenTop: 900, screens: screens)
        XCTAssertEqual(caret.point, CGPoint(x: -100, y: 590))
        XCTAssertFalse(caret.usedMouseFallback)
        for rect: CGRect? in [
            nil, .zero, CGRect(x: CGFloat.infinity, y: 0, width: 0, height: 20),
            CGRect(x: 2000, y: 0, width: 0, height: 20),
        ] {
            let fallback = MenuAnchor(
                mode: .caret, mouse: mouse, caretBounds: rect, primaryScreenTop: 900, screens: screens)
            XCTAssertEqual(fallback.point, mouse)
            XCTAssertTrue(fallback.usedMouseFallback)
        }
        XCTAssertEqual(
            MenuAnchor(
                mode: .mouse, mouse: mouse, caretBounds: bounds,
                primaryScreenTop: 900, screens: screens
            ).point, mouse)
    }
}
