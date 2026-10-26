import AppKit
import XCTest
@testable import PhrasePerch

final class WheelTitleSettingsTests: XCTestCase {
    private final class RecordingLayer: CALayer {
        var recorded: CAAnimationGroup?
        override func add(_ animation: CAAnimation, forKey key: String?) {
            recorded = animation as? CAAnimationGroup
            super.add(animation, forKey: key)
        }
    }
    func testTitleLimitCountsGraphemesAndKeepsOneLine() {
        for limit in [1, 10, 30] {
            let title = String(repeating: "👩🏽‍💻中a", count: 12)
            let visible = floatingButtonTitle(title, characterLimit: limit)
            XCTAssertEqual(visible, String(title.prefix(limit)) + "…")
        }
        XCTAssertEqual(floatingButtonTitle("第一行\r\n第二行\t末尾", characterLimit: 30), "第一行 第二行 末尾")
    }
    func testWidthsExtendFromInnerEdgeAndPreserveMinimumGaps() throws {
        for count in 1...8 {
            let widths = (0..<count).map { CGFloat(88 + $0 * 23) }
            for direction in [CGFloat(0), .pi / 5] {
                let layout = CircularButtonLayout.outwardItems(widths: widths, height: 40, angle: direction)
                let base = CircularButtonLayout.items(count: count, buttonSize: CGSize(width: 88, height: 40), angle: direction)
                XCTAssertFalse(base.isEmpty)
                let baseRadius = hypot(base[0].midX, base[0].midY)
                XCTAssertEqual(layout.items.count, count)
                for (index, rect) in layout.items.enumerated() {
                    let x = base[index].midX * layout.radius / baseRadius
                    if abs(x) < 0.0001 { XCTAssertEqual(rect.midX, x, accuracy: 0.001) }
                    else if x > 0 { XCTAssertEqual(rect.minX, x - 44, accuracy: 0.001) }
                    else { XCTAssertEqual(rect.maxX, x + 44, accuracy: 0.001) }
                    XCTAssertEqual(rect.width, widths[index])
                    for other in layout.items.dropFirst(index + 1) {
                        XCTAssertGreaterThanOrEqual(CircularButtonLayout.edgeGap(rect, other), 12)
                    }
                }
            }
        }
    }
    @MainActor
    func testLongTitlesFitCornersAndNavigationLabelsStayComplete() throws {
        let nodes = (0..<12).map { RadialNode.content(Snippet(title: String(repeating: $0.isMultiple(of: 2) ? "👩‍💻" : "长标题", count: 20), text: "正文")) }
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -900, y: -200, width: 320, height: 240)] {
            for limit in [1, 10, 30] {
                for anchor in [CGPoint(x: screen.minX + 1, y: screen.minY + 1), CGPoint(x: screen.maxX - 1, y: screen.maxY - 1)] {
                    let page = try XCTUnwrap(RadialPage(nodes: nodes, anchor: anchor, visible: screen,
                        hasPrevious: true, previousAngle: .pi / 4, characterLimit: limit))
                    XCTAssertLessThanOrEqual(page.characterLimit, limit)
                    XCTAssertTrue(page.layout.items.allSatisfy(screen.insetBy(dx: 8, dy: 8).contains))
                    for (slot, node) in page.slots.enumerated() {
                        if node?.action == .previous { XCTAssertEqual(page.titles[slot], RadialNode.previous.title) }
                        if node?.action == .next { XCTAssertEqual(page.titles[slot], RadialNode.next.title) }
                    }
                    let view = FloatingMenuView(frame: .zero)
                    view.configure(slots: page.slots, layout: page.layout, titles: page.titles)
                    for button in view.buttons {
                        XCTAssertFalse(button.title.contains("\n"))
                        XCTAssertNotNil(view.interactiveIndex(CGPoint(x: button.frame.midX, y: button.frame.midY)))
                    }
                }
            }
        }
    }
    @MainActor
    func testBackwardAnimationMirrorsAnglesAndPreservesScaleAndTiming() throws {
        let layout = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 400, y: 300), visible: CGRect(x: 0, y: 0, width: 1200, height: 800), count: 6))
        func motion(_ direction: FloatingMenuAnimationConfiguration.Direction) throws -> CAKeyframeAnimation {
            let layer = RecordingLayer()
            let animator = FloatingMenuAnimator(scheduler: ManualAnimationScheduler(), reduceMotion: { false })
            animator.animate(layer: layer, layout: layout, expanding: true, direction: direction) {}
            let group = try XCTUnwrap(layer.recorded)
            XCTAssertEqual(group.duration, 0.42)
            animator.cancel()
            return try XCTUnwrap(group.animations?.first as? CAKeyframeAnimation)
        }
        let first = try motion(.forward), second = try motion(.backward)
        XCTAssertEqual(first.keyTimes, second.keyTimes)
        for (a, b) in zip(try XCTUnwrap(first.values as? [NSValue]), try XCTUnwrap(second.values as? [NSValue])) {
            let a = a.caTransform3DValue, b = b.caTransform3DValue
            XCTAssertEqual(a.m11, b.m11, accuracy: 0.000001)
            XCTAssertEqual(a.m12, -b.m12, accuracy: 0.000001)
            XCTAssertEqual(a.m21, -b.m21, accuracy: 0.000001)
        }
    }
}
