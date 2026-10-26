import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class FloatingMenuTests: PresentationTestCase {
    @MainActor
    func testSingleLineTitlesFitAtOneFontSizeInMenuAndEditor() throws {
        let titles = ["继续", "详细解释一下", "请详细解释一下", "请检查并解释这段代码", String(repeating: "标题", count: 10),
            "Explain this code", "ThisIsAnUnbrokenTitle", "👩‍💻👨‍👩‍👧‍👦快速回复和检查代码", "第一行\n第二行"]
        for height in [RadialLayout.buttonSize.height, EditorRingLayout.buttonSize.height] {
            for title in titles + [String(repeating: "👩‍💻", count: 10)] {
                let display = floatingButtonTitle(title)
                let size = CGSize(width: snippetButtonWidth(for: [title]), height: height)
                XCTAssertFalse(display.contains("\n"))
                let measured = (display as NSString).size(withAttributes: [
                    .font: NSFont.systemFont(ofSize: snippetTitleFontSize, weight: .medium)])
                XCTAssertLessThanOrEqual(measured.width, size.width - 12)
                XCTAssertLessThanOrEqual(measured.height, size.height - 8)
            }
        }
        let controller = FloatingMenuWindowController()
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "preview.titles", fallbackBundlePath: nil),
            displayName: "Preview", buttons: titles.prefix(6).map { Snippet(title: $0, text: "正文") })
        XCTAssertTrue(controller.configure(profile: profile, at: CGPoint(x: 500, y: 400), visible: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        let root = try XCTUnwrap(controller.panel.contentView as? FloatingMenuView)
        XCTAssertEqual(root.buttons.map(\.title), Array(titles.prefix(6)).map(floatingButtonTitle))
        try savePreview(root, name: "radial-single-line-titles.png")
        (root.buttons[4] as? FloatingMenuButton)?.selected = true
        try savePreview(root, name: "radial-single-line-titles-selected.png")
    }

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
            for count in [1, 3, 6, 8] {
                for point in points {
                    let layout = try XCTUnwrap(RadialLayout(anchor: point, visible: visible, count: count))
                    XCTAssertEqual(layout.items.count, count)
                    XCTAssertEqual(layout.anchor, point)
                    XCTAssertTrue(visible.contains(layout.frame))
                    XCTAssertNil(layout.selectedIndex(at: layout.center))
                    let radius = try XCTUnwrap(layout.items.first).midY - layout.center.y
                    for (index, rect) in layout.items.enumerated() {
                        if index < 6 { XCTAssertEqual(hypot(rect.midX - layout.center.x, rect.midY - layout.center.y), radius, accuracy: 0.001) }
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
        for count in [1, 3, 6, 8] {
            let middle = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 720, y: 450), visible: screen, count: count))
            let edge = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 1, y: 1), visible: screen, count: count))
            for (a, b) in zip(middle.items, edge.items) {
                XCTAssertEqual(a.midX - middle.center.x, b.midX - edge.center.x, accuracy: 0.001)
                XCTAssertEqual(a.midY - middle.center.y, b.midY - edge.center.y, accuracy: 0.001)
            }
            let radius = hypot(middle.items[0].midX - middle.center.x, middle.items[0].midY - middle.center.y)
            XCTAssertLessThan(radius, 180)
            for rect in middle.items.prefix(6) {
                XCTAssertEqual(hypot(rect.midX - middle.center.x, rect.midY - middle.center.y), radius, accuracy: 0.001)
            }
        }
    }

    func testAuthorizationCardFitsNegativeCoordinateDisplay() {
        let visible = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let frame = authorizationGuideFrame(
            settings: CGRect(x: -900, y: -180, width: 800, height: 800), visible: visible)
        XCTAssertTrue(visible.contains(frame))
    }

    @MainActor
    func testAuthorizationPlacementTracksDiscoveryMovementResizeAndScreen() throws {
        let guide = AuthorizationGuideWindowController()
        defer { guide.hide() }
        let url = Bundle.main.bundleURL
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1200)
        guide.updatePlacement(applicationURL: url, settings: nil, visible: screen)
        XCTAssertTrue(screen.contains(guide.panel.frame))
        for settings in [CGRect(x: 200, y: 100, width: 740, height: 1050),
            CGRect(x: 400, y: 140, width: 740, height: 1050), CGRect(x: 400, y: 140, width: 600, height: 800)] {
            guide.updatePlacement(applicationURL: url, settings: settings, visible: screen)
            let expected = authorizationGuideFrame(settings: settings, visible: screen)
            XCTAssertEqual(expected.midX, settings.minX + settings.width * 0.66, accuracy: 0.001)
            XCTAssertEqual(expected.midY, settings.minY + settings.height * 0.2, accuracy: 0.001)
            // AppKit aligns native windows to display pixels.
            XCTAssertEqual(guide.panel.frame.midX, expected.midX, accuracy: 1)
            XCTAssertEqual(guide.panel.frame.midY, expected.midY, accuracy: 1)
            XCTAssertTrue(settings.contains(guide.panel.frame))
            XCTAssertEqual(guide.panel.contentView?.frame.size, guide.panel.frame.size)
            let drag = try XCTUnwrap(guide.panel.contentView?.subviews.compactMap { $0 as? ApplicationDragView }.first)
            XCTAssertEqual(drag.applicationURL, url)
            XCTAssertLessThanOrEqual(drag.frame.maxX, guide.panel.frame.width)
        }
        let other = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let settings = CGRect(x: -1200, y: -100, width: 700, height: 700)
        guide.updatePlacement(applicationURL: url, settings: settings, visible: other)
        XCTAssertTrue(other.contains(guide.panel.frame))
        XCTAssertTrue(settings.contains(guide.panel.frame))
        try savePreview(try XCTUnwrap(guide.panel.contentView), name: "authorization-positioned.png")
    }
}
