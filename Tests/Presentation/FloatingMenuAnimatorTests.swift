import AppKit
import XCTest

@testable import PhrasePerch

final class FloatingMenuAnimatorTests: XCTestCase {
    @MainActor
    func testWholeWheelUsesApprovedKeyframesAndFadeOnlyReducedMotion() throws {
        let layout = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 1, y: 1),
            visible: CGRect(x: 0, y: 0, width: 1000, height: 800), count: 6))
        for reduced in [false, true] {
            let scheduler = ManualAnimationScheduler()
            let animator = FloatingMenuAnimator(scheduler: scheduler, reduceMotion: { reduced })
            let layer = CALayer()
            animator.animate(layer: layer, layout: layout, expanding: true) {}
            let group = try XCTUnwrap(layer.animation(forKey: "radialMotion") as? CAAnimationGroup)
            XCTAssertEqual(group.duration, reduced ? 0.08 : 0.42)
            XCTAssertTrue(CATransform3DIsIdentity(layer.transform))
            XCTAssertEqual(layer.opacity, 1)
            if reduced {
                XCTAssertEqual(group.animations?.count, 1)
                XCTAssertEqual((group.animations?.first as? CABasicAnimation)?.keyPath, "opacity")
            } else {
                let keyframes = try XCTUnwrap(group.animations as? [CAKeyframeAnimation])
                XCTAssertEqual(keyframes.count, 2)
                let motion = try XCTUnwrap(keyframes.first { $0.keyPath == "transform" })
                let times = try XCTUnwrap(motion.keyTimes)
                let values = try XCTUnwrap(motion.values as? [NSValue]).map(\.caTransform3DValue)
                for (time, angle, scale) in [(0.0, 55.0, 0.24), (0.69, 0, 1), (0.84, -3, 1.015), (1, 0, 1)] {
                    let index = try XCTUnwrap(times.firstIndex(of: NSNumber(value: time)))
                    XCTAssertEqual(atan2(values[index].m12, values[index].m11), angle * .pi / 180, accuracy: 0.000001)
                    XCTAssertEqual(hypot(values[index].m11, values[index].m12), scale, accuracy: 0.000001)
                }
                for (time, value) in zip(times, values) {
                    let scale = hypot(value.m11, value.m12)
                    let travel = time.doubleValue < 0.69 ? (1 - scale) / (1 - 0.24) : 0
                    let center = layout.localCenter.applying(CATransform3DGetAffineTransform(value))
                    XCTAssertEqual(center.x, layout.localCenter.x + (layout.anchor.x - layout.center.x) * travel, accuracy: 0.0001)
                    XCTAssertEqual(center.y, layout.localCenter.y + (layout.anchor.y - layout.center.y) * travel, accuracy: 0.0001)
                }
            }
            animator.animate(layer: layer, layout: layout, expanding: false) {}
            let closing = try XCTUnwrap(layer.animation(forKey: "radialMotion") as? CAAnimationGroup)
            XCTAssertEqual(closing.duration, reduced ? 0.08 : 0.12)
            if reduced {
                XCTAssertEqual(closing.animations?.count, 1)
                XCTAssertTrue(CATransform3DIsIdentity(layer.transform))
            } else {
                let center = layout.localCenter.applying(CATransform3DGetAffineTransform(layer.transform))
                XCTAssertEqual(center.x, layout.localAnchor.x, accuracy: 0.0001)
                XCTAssertEqual(center.y, layout.localAnchor.y, accuracy: 0.0001)
            }
        }
    }

    @MainActor
    func testCollapseContinuesCurrentWheelTransformAndOpacity() throws {
        let layout = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 300, y: 300),
            visible: CGRect(x: 0, y: 0, width: 1000, height: 800), count: 6))
        let layer = CALayer()
        let current = CATransform3DScale(CATransform3DMakeRotation(0.4, 0, 0, 1), 0.7, 0.7, 1)
        layer.transform = current
        layer.opacity = 0.6
        let animator = FloatingMenuAnimator(scheduler: ManualAnimationScheduler(), reduceMotion: { false })
        animator.animate(layer: layer, layout: layout, expanding: false) {}
        let group = try XCTUnwrap(layer.animation(forKey: "radialMotion") as? CAAnimationGroup)
        let motion = try XCTUnwrap(group.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "transform" })
        let from = try XCTUnwrap(motion.fromValue as? NSValue).caTransform3DValue
        XCTAssertTrue(CATransform3DEqualToTransform(from, current))
        let fade = try XCTUnwrap(group.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "opacity" })
        XCTAssertEqual(try XCTUnwrap(fade.fromValue as? Float), 0.6, accuracy: 0.0001)
    }

    @MainActor
    func testTransformedHitTestingAndReconfigurationWithEmptySlots() throws {
        let layout = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 1, y: 1),
            visible: CGRect(x: 0, y: 0, width: 1000, height: 800), count: 6, buttonWidth: 132))
        let slots: [RadialNode?] = (0..<6).map { $0 == 1 ? nil : .content(Snippet(title: "文案 \($0)", text: "正文")) }
        let view = FloatingMenuView(frame: .zero)
        view.configure(slots: slots, layout: layout)
        let layer = try XCTUnwrap(view.animationLayer)
        for angle in [0.0, 0.4, -0.7] {
            layer.setAffineTransform(CGAffineTransform(translationX: -12, y: 9).rotated(by: angle).scaledBy(x: 0.7, y: 0.7))
            for (index, button) in view.buttons.enumerated() {
                let center = layer.convert(CGPoint(x: button.frame.midX, y: button.frame.midY), to: layer.superlayer)
                XCTAssertEqual(view.interactiveIndex(center), index)
                let corner = layer.convert(CGPoint(x: button.frame.minX + 1, y: button.frame.minY + 1), to: layer.superlayer)
                XCTAssertNil(view.interactiveIndex(corner))
            }
            let empty = layout.itemRect(index: 1)
            XCTAssertNil(view.interactiveIndex(layer.convert(CGPoint(x: empty.midX, y: empty.midY), to: layer.superlayer)))
            XCTAssertNil(view.interactiveIndex(layer.convert(layout.localCenter, to: layer.superlayer)))
        }
        layer.opacity = 0.04
        XCTAssertNil(view.interactiveIndex(layout.localCenter))
        layer.add(CABasicAnimation(keyPath: "opacity"), forKey: "radialMotion")
        view.configure(slots: slots, layout: layout)
        XCTAssertTrue(CATransform3DIsIdentity(layer.transform))
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertNil(layer.animation(forKey: "radialMotion"))
        let rings = try XCTUnwrap(layer.sublayers?.compactMap { $0 as? CAShapeLayer })
        XCTAssertEqual(rings.count, 1)
        XCTAssertEqual(rings.first?.lineWidth, 0.5)
        XCTAssertEqual(try XCTUnwrap(rings.first?.strokeColor?.alpha), 0.045, accuracy: 0.0001)
        XCTAssertEqual(view.buttons.count, 5)
        for button in view.buttons { XCTAssertTrue(button.layer?.animationKeys()?.isEmpty ?? true) }
    }

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
        animator.animate(layer: button.layer, layout: layout, expanding: true) { completed.append(0) }
        animator.animate(layer: button.layer, layout: layout, expanding: false) { completed.append(1) }
        animator.animate(layer: button.layer, layout: layout, expanding: true) { completed.append(2) }
        scheduler.finish(0)
        scheduler.finish(1)
        XCTAssertTrue(completed.isEmpty)
        XCTAssertNotNil(button.layer?.animation(forKey: "radialMotion"))
        scheduler.finish(2)
        XCTAssertEqual(completed, [2])
        XCTAssertNil(button.layer?.animation(forKey: "radialMotion"))
        animator.animate(layer: button.layer, layout: layout, expanding: false) { completed.append(3) }
        animator.cancel()
        scheduler.finish(3)
        XCTAssertEqual(completed, [2])
        let configuration = FloatingMenuAnimationConfiguration()
        XCTAssertEqual(configuration.duration(expanding: true, reduced: false), 0.42)
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
        XCTAssertEqual(model.page?.remaining.compactMap(\.contentID), [first.id])
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
