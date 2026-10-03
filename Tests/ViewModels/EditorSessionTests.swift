import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class EditorSessionTests: PresentationTestCase {
    func testEditorSelectionPaginationDeletionReorderAndPerAppMemory() {
        var ids = (0..<17).map { _ in UUID() }
        var session = SnippetEditorSession()
        session.reconcile(ids)
        XCTAssertEqual(session.selectedID, ids[0])
        XCTAssertEqual(SnippetEditorSession.pageCount(0), 1)
        XCTAssertEqual(SnippetEditorSession.pageCount(8), 1)
        XCTAssertEqual(SnippetEditorSession.pageCount(9), 2)
        XCTAssertEqual(SnippetEditorSession.pageCount(17), 3)
        session.select(ids[16], in: ids)
        XCTAssertEqual(session.page, 2)
        ids.removeLast()
        session.deleted(at: 16, remaining: ids)
        XCTAssertEqual(session.selectedID, ids[15])
        XCTAssertEqual(session.page, 1)
        session.showPage(0, in: ids)
        XCTAssertEqual(session.selectedID, ids[0])
        session.select(ids[7], in: ids)
        let selected = ids[7]
        ids.swapAt(7, 8)
        session.reconcile(ids)
        XCTAssertEqual(session.selectedID, selected)
        XCTAssertEqual(session.page, 1)
        let appA = UUID()
        let appB = UUID()
        var sessions = [appA: session, appB: SnippetEditorSession()]
        sessions[appB]?.reconcile([UUID()])
        XCTAssertEqual(sessions[appA], session)
        session.reconcile([])
        XCTAssertNil(session.selectedID)
        XCTAssertEqual(session.page, 0)
    }

    func testSnippetDeletionRequiresConfirmationAndRetainsCorrectSelection() {
        var profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.deletion", fallbackBundlePath: nil),
            displayName: "Delete", buttons: (0..<17).map { Snippet(title: "文案\($0)", text: "正文") })
        let original = profile
        var session = SnippetEditorSession()
        session.select(profile.buttons[8].id, in: profile.buttons.map(\.id))
        var deletion = SnippetDeletion()
        let target = profile.buttons[8].id
        let adjacent = profile.buttons[9].id
        deletion.request(target)
        XCTAssertEqual(profile, original, "A deletion request must not modify the profile")
        deletion.cancel()
        XCTAssertNil(deletion.id)
        XCTAssertEqual(profile, original)
        deletion.request(target)
        // SwiftUI can clear presentation state while dismissing the confirmation.
        // The confirmed alert payload must still identify the original item.
        deletion.cancel()
        deletion.confirm(target, profile: &profile, session: &session)
        XCTAssertEqual(profile.buttons.count, 16)
        XCTAssertFalse(profile.buttons.contains { $0.id == target })
        XCTAssertEqual(session.selectedID, adjacent)
        XCTAssertEqual(session.page, 1)
        XCTAssertNil(deletion.id)
        let remaining = profile
        deletion.request(target)
        deletion.confirm(target, profile: &profile, session: &session)
        XCTAssertEqual(profile, remaining, "A stale confirmation must not remove a different item")
        profile.buttons = [profile.buttons[0]]
        session.reconcile(profile.buttons.map(\.id))
        let lastID = profile.buttons[0].id
        deletion.request(lastID)
        deletion.confirm(lastID, profile: &profile, session: &session)
        XCTAssertTrue(profile.buttons.isEmpty)
        XCTAssertNil(session.selectedID)
        XCTAssertEqual(session.page, 0)
    }
}
