import AppKit
import XCTest

@testable import PhrasePerch

final class FloatingMenuAnimatorTests: XCTestCase {
    @MainActor
    func testOldAnimationCallbacksCannotCompleteNewPresentation() throws {
        let scheduler = ManualAnimationScheduler()
        let animator = FloatingMenuAnimator(scheduler: scheduler)
        let layout = try XCTUnwrap(
            RadialLayout(
                anchor: CGPoint(x: 300, y: 300),
                visible: CGRect(x: 0, y: 0, width: 1000, height: 800), count: 1))
        let button = NSButton(frame: layout.itemRect(index: 0))
        button.wantsLayer = true
        var completed: [Int] = []
        animator.animate(buttons: [button], layout: layout, expanding: true) { completed.append(0) }
        animator.animate(buttons: [button], layout: layout, expanding: false) { completed.append(1) }
        animator.animate(buttons: [button], layout: layout, expanding: true) { completed.append(2) }
        scheduler.finish(0)
        scheduler.finish(1)
        XCTAssertTrue(completed.isEmpty)
        scheduler.finish(2)
        XCTAssertEqual(completed, [2])
        animator.animate(buttons: [button], layout: layout, expanding: false) { completed.append(3) }
        animator.cancel()
        scheduler.finish(3)
        XCTAssertEqual(completed, [2])
        let configuration = FloatingMenuAnimationConfiguration()
        XCTAssertEqual(configuration.duration(expanding: true, reduced: false), 0.18)
        XCTAssertEqual(configuration.duration(expanding: false, reduced: false), 0.12)
        XCTAssertEqual(configuration.duration(expanding: true, reduced: true), 0.08)
        XCTAssertEqual(configuration.duration(expanding: false, reduced: true), 0.08)
    }

    @MainActor
    func testFloatingMenuSelectionAndSessionDoNotDependOnAWindow() throws {
        let first = Snippet(title: "启用", text: "正文")
        let disabled = Snippet(title: "停用", text: "正文", isEnabled: false)
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.menu", fallbackBundlePath: nil),
            displayName: "Test", buttons: [first, disabled])
        let model = FloatingMenuViewModel()
        XCTAssertTrue(
            model.configure(
                profile: profile, at: CGPoint(x: 300, y: 300),
                visible: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        XCTAssertEqual(model.snippets.map(\.id), [first.id])
        let old = model.beginShow(initialMouse: CGPoint(x: 300, y: 300), requiresMovement: true)
        XCTAssertNil(model.select(at: CGPoint(x: 300, y: 300), hitID: first.id))
        XCTAssertEqual(model.select(at: CGPoint(x: 350, y: 350), hitID: first.id), first.id)
        let hide = model.beginHide()
        let new = model.beginShow(initialMouse: .zero, requiresMovement: false)
        XCTAssertFalse(model.finishShow(old))
        XCTAssertFalse(model.finishHide(hide))
        XCTAssertTrue(model.finishShow(new))
        XCTAssertTrue(model.isPresented)
        XCTAssertNil(model.select(at: .zero, hitID: disabled.id))
    }
}
