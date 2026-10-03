import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class FloatingMenuTests: PresentationTestCase {
    func testRadialGeometryAllItemsAndScreenEdges() throws {
        for visible in [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: -1440, y: -200, width: 1440, height: 900),
        ] {
            let points = [
                CGPoint(x: visible.midX, y: visible.midY),
                CGPoint(x: visible.minX + 1, y: visible.minY + 1),
                CGPoint(x: visible.maxX - 1, y: visible.minY + 1),
                CGPoint(x: visible.minX + 1, y: visible.maxY - 1),
                CGPoint(x: visible.maxX - 1, y: visible.maxY - 1),
            ]
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
        let firstShow = state.show()
        let oldHide = state.hide()
        let newShow = state.show()
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

    func testAuthorizationCardFitsNegativeCoordinateDisplay() {
        let visible = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let frame = authorizationGuideFrame(
            settings: CGRect(x: -900, y: -180, width: 800, height: 800), visible: visible)
        XCTAssertTrue(visible.contains(frame))
    }
}
