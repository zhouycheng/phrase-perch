import AppKit
import XCTest
@testable import PhrasePerch

final class RadialPagingTests: PresentationTestCase {
    func testDirectedTemplatesKeepClearanceAndOppositeSlots() throws {
        for width: CGFloat in [88, 132, 210] {
            for count in 1...8 {
                for direction in 0..<16 {
                    let angle = CGFloat(direction) * .pi / 8
                    let pin = count - 1
                    let items = CircularButtonLayout.items(count: count,
                        buttonSize: CGSize(width: width, height: 40), pinnedIndex: pin, angle: angle)
                    XCTAssertEqual(items.count, count)
                    guard items.count == count else { continue }
                    let radius = hypot(items[pin].midX, items[pin].midY)
                    XCTAssertEqual(items[pin].midX / radius, sin(angle), accuracy: 0.0001)
                    XCTAssertEqual(-items[pin].midY / radius, cos(angle), accuracy: 0.0001)
                    var gaps: [CGFloat] = []
                    for (index, item) in items.enumerated() {
                        XCTAssertEqual(hypot(item.midX, item.midY), radius, accuracy: 0.001)
                        XCTAssertFalse(item.intersects(CGRect(x: -24, y: -24, width: 48, height: 48)))
                        for other in items.dropFirst(index + 1) {
                            XCTAssertGreaterThanOrEqual(CircularButtonLayout.edgeGap(item, other), 12)
                        }
                        if count > 1 { gaps.append(CircularButtonLayout.edgeGap(item, items[(index + 1) % count])) }
                        if count.isMultiple(of: 2) {
                            let opposite = items[(index + count / 2) % count]
                            XCTAssertEqual(item.midX, -opposite.midX, accuracy: 0.001)
                            XCTAssertEqual(item.midY, -opposite.midY, accuracy: 0.001)
                        }
                    }
                    if let min = gaps.min(), let max = gaps.max() {
                        XCTAssertLessThan(max - min, 1, "width=\(width), count=\(count), direction=\(direction)")
                    }
                }
            }
        }
    }

    @MainActor
    func testPreviousFacesEntryAndNextStaysOppositeAcrossScreenEdges() throws {
        let screen = CGRect(x: -1400, y: -300, width: 1400, height: 900)
        for direction in 0..<8 {
            let angle = CGFloat(direction) * .pi / 4
            for count in [1, 2, 3, 4, 5, 6, 7, 8, 31] {
                let nodes = (0..<count).map { RadialNode.content(Snippet(title: "文案 \($0)", text: "正文")) }
                for anchor in [CGPoint(x: screen.minX + 1, y: screen.minY + 1),
                    CGPoint(x: screen.maxX - 1, y: screen.maxY - 1)] {
                    let page = try XCTUnwrap(RadialPage(nodes: nodes, anchor: anchor,
                        visible: screen, hasPrevious: true, previousAngle: angle))
                    let previous = page.layout.items[try XCTUnwrap(page.slots.firstIndex { $0?.action == .previous })]
                    let center = page.layout.center
                    let radius = hypot(previous.midX - center.x, previous.midY - center.y)
                    XCTAssertEqual((previous.midX - center.x) / radius, sin(angle), accuracy: 0.0001)
                    XCTAssertEqual((previous.midY - center.y) / radius, cos(angle), accuracy: 0.0001)
                    XCTAssertTrue(page.layout.items.allSatisfy(screen.insetBy(dx: 8, dy: 8).contains))
                    if [2, 3].contains(direction), [4, 31].contains(count), anchor.x == screen.minX + 1 {
                        let view = FloatingMenuView(frame: .zero)
                        view.configure(slots: page.slots, layout: page.layout)
                        try savePreview(view, name: "radial-entry-\(direction)-\(count).png")
                    }
                    if let index = page.slots.firstIndex(where: { $0?.action == .next }) {
                        let next = page.layout.items[index]
                        XCTAssertEqual(previous.midX + next.midX, 2 * center.x, accuracy: 0.001)
                        XCTAssertEqual(previous.midY + next.midY, 2 * center.y, accuracy: 0.001)
                    }
                    let moved = try XCTUnwrap(page.relocated(at: CGPoint(x: screen.midX, y: screen.midY),
                        visible: screen, previousAngle: angle + .pi))
                    XCTAssertEqual(moved.slots, page.slots)
                    XCTAssertEqual(moved.remaining, page.remaining)
                    XCTAssertEqual(moved.consumed, page.consumed)
                    let back = moved.layout.items[try XCTUnwrap(moved.slots.firstIndex { $0?.action == .previous })]
                    let backRadius = hypot(back.midX - moved.layout.center.x, back.midY - moved.layout.center.y)
                    XCTAssertEqual((back.midX - moved.layout.center.x) / backRadius, sin(angle + .pi), accuracy: 0.001)
                    XCTAssertEqual((back.midY - moved.layout.center.y) / backRadius, cos(angle + .pi), accuracy: 0.001)
                }
            }
        }
    }
    func testRelocatingHistoryPreservesContentAndFitsScreenCorners() throws {
        let screen = CGRect(x: -1400, y: -300, width: 1400, height: 900)
        let nodes = (0..<31).map { RadialNode.content(Snippet(title: "文案 \($0)", text: "正文")) }
        let original = try XCTUnwrap(RadialPage(nodes: nodes,
            anchor: CGPoint(x: screen.midX, y: screen.midY), visible: screen, hasPrevious: true))
        for x in [screen.minX + 1, screen.midX, screen.maxX - 1] {
            for y in [screen.minY + 1, screen.midY, screen.maxY - 1] {
                let anchor = CGPoint(x: x, y: y)
                let moved = try XCTUnwrap(original.relocated(at: anchor, visible: screen))
                XCTAssertEqual(moved.layout.anchor, anchor)
                XCTAssertEqual(moved.slots, original.slots)
                XCTAssertEqual(moved.remaining, original.remaining)
                XCTAssertEqual(moved.consumed, original.consumed)
                for (before, after) in zip(original.layout.items, moved.layout.items) {
                    XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(after))
                    XCTAssertEqual(before.midX - original.layout.center.x, after.midX - moved.layout.center.x, accuracy: 0.001)
                    XCTAssertEqual(before.midY - original.layout.center.y, after.midY - moved.layout.center.y, accuracy: 0.001)
                }
            }
        }
        XCTAssertNil(original.relocated(at: .zero, visible: CGRect(x: -10, y: -10, width: 20, height: 20)))
    }
    @MainActor
    func testPreviousAndNextAreOppositeInNodeCenteredPages() throws {
        for count in [2, 7, 8, 9, 31, 512] {
            let nodes = (0..<count).map { RadialNode.content(Snippet(title: "文案 \($0)", text: "正文")) }
            for visible in [CGRect(x: 0, y: 0, width: 1400, height: 900),
                CGRect(x: -800, y: -300, width: 320, height: 240)] {
                let page = try XCTUnwrap(RadialPage(nodes: nodes,
                    anchor: CGPoint(x: visible.midX, y: visible.midY), visible: visible, hasPrevious: true))
                guard page.hasNext else { continue }
                let next = page.layout.items[try XCTUnwrap(page.slots.firstIndex { $0?.action == .next })]
                let previous = page.layout.items[try XCTUnwrap(page.slots.firstIndex { $0?.action == .previous })]
                let center = page.layout.center
                XCTAssertEqual(page.slots.count % 2, 0)
                XCTAssertEqual(next.midX, center.x, accuracy: 0.001)
                XCTAssertGreaterThan(next.midY, center.y)
                XCTAssertEqual(next.midX + previous.midX, center.x * 2, accuracy: 0.001)
                XCTAssertEqual(next.midY + previous.midY, center.y * 2, accuracy: 0.001)
                XCTAssertEqual(page.slots.compactMap { $0?.contentID }, Array(nodes.prefix(page.consumed)).compactMap(\.contentID))
                if count == 31 && visible.width == 1400 {
                    let view = FloatingMenuView(frame: .zero)
                    view.configure(slots: page.slots, layout: page.layout)
                    try savePreview(view, name: "radial-opposite-navigation.png")
                }
            }
        }
    }

    @MainActor
    func testTriangleDiamondAndAllNodeCountPreviews() throws {
        for count in 1...8 {
            let nodes = (0..<count).map { RadialNode.content(Snippet(title: "文案 \($0 + 1)", text: "正文")) }
            let page = try XCTUnwrap(RadialPage(nodes: nodes, anchor: CGPoint(x: 400, y: 300),
                visible: CGRect(x: 0, y: 0, width: 800, height: 600)))
            let center = page.layout.center, items = page.layout.items
            XCTAssertEqual(items[0].midX, center.x, accuracy: 0.001)
            XCTAssertGreaterThan(items[0].midY, center.y)
            if count == 3 {
                XCTAssertEqual(items[1].midY, items[2].midY, accuracy: 0.001)
                XCTAssertLessThan(items[1].midY, center.y)
            }
            if count == 4 {
                XCTAssertEqual(items[1].midY, center.y, accuracy: 0.001)
                XCTAssertEqual(items[2].midX, center.x, accuracy: 0.001)
                XCTAssertEqual(items[3].midY, center.y, accuracy: 0.001)
            }
            let view = FloatingMenuView(frame: .zero)
            view.configure(slots: page.slots, layout: page.layout)
            try savePreview(view, name: "radial-count-\(count).png")
        }
    }

    func testSingleRingClearanceAndPageCapacity() throws {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: -1440, y: -200, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 900, height: 1440)] {
            for count in [1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 512] {
                let layout = try XCTUnwrap(RadialLayout.fittingPage(anchor: CGPoint(x: screen.minX + 1, y: screen.minY + 1),
                    visible: screen, count: count, buttonWidth: 120))
                XCTAssertLessThanOrEqual(layout.items.count, count)
                XCTAssertEqual(layout.items.count, min(count, 8))
                XCTAssertTrue(screen.contains(layout.frame))
                for (index, item) in layout.items.enumerated() {
                    XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(item))
                    for other in layout.items.dropFirst(index + 1) {
                        XCTAssertGreaterThanOrEqual(CircularButtonLayout.edgeGap(item, other), 12)
                    }
                }
                let radii = layout.items.map { hypot($0.midX - layout.center.x, $0.midY - layout.center.y) }
                for radius in radii { XCTAssertEqual(radius, radii[0], accuracy: 0.001) }
                if layout.items.count > 1 {
                    let gaps = layout.items.indices.map {
                        CircularButtonLayout.edgeGap(layout.items[$0], layout.items[($0 + 1) % layout.items.count])
                    }
                    XCTAssertLessThan(try XCTUnwrap(gaps.max()) - XCTUnwrap(gaps.min()), 1)
                }
            }
        }
        XCTAssertNil(RadialLayout.fittingPage(anchor: .zero, visible: CGRect(x: 0, y: 0, width: 100, height: 100), count: 30, buttonWidth: 88))
    }

    @MainActor
    func testPersistentButtonsAndAccessibleSelection() throws {
        let snippets = (0..<6).map { Snippet(title: "文案 \($0)", text: "中文 👩‍💻\n第二行") }
        let layout = try XCTUnwrap(RadialLayout(anchor: CGPoint(x: 600, y: 450),
            visible: CGRect(x: 0, y: 0, width: 1200, height: 900), count: 6))
        let view = FloatingMenuView(frame: .zero)
        var chosen: UUID?
        view.onSelect = { if case .content(let id) = $0 { chosen = id } }
        view.configure(slots: snippets.map { RadialNode.content($0) }, layout: layout)
        XCTAssertFalse(view.buttons[0].accessibilityPerformPress())
        XCTAssertNil(chosen)
        view.allowsClick = true
        view.configure(slots: snippets.map { RadialNode.content($0) }, layout: layout)
        XCTAssertTrue(view.buttons[0].accessibilityPerformPress())
        XCTAssertEqual(chosen, snippets[0].id)
        XCTAssertEqual(view.buttons[5].accessibilityLabel(), snippets[5].title)
        try savePreview(view, name: "radial-single-ring.png")
    }

    @MainActor
    func testNextPageExpandsAtNodeAndReturnRestoresPage() throws {
        let scheduler = ManualAnimationScheduler()
        let controller = FloatingMenuWindowController(animator: FloatingMenuAnimator(scheduler: scheduler))
        let snippets = (0..<31).map { Snippet(title: "文案 \($0)", text: "正文") }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.paging", fallbackBundlePath: nil),
            displayName: "Test", buttons: snippets)
        XCTAssertTrue(controller.configure(profile: profile, at: CGPoint(x: 700, y: 450),
            visible: CGRect(x: 0, y: 0, width: 1400, height: 900)))
        _ = controller.viewModel.beginShow(initialMouse: .zero, requiresMovement: false)
        let root = try XCTUnwrap(controller.viewModel.page)
        var ids = controller.pageNodes.compactMap(\.contentID)
        var steps = 0
        while controller.hasNextPage, steps < 30 {
            let previous = try XCTUnwrap(controller.layout)
            let next = try XCTUnwrap((controller.panel.contentView as? FloatingMenuView)?.buttons.compactMap { $0 as? FloatingMenuButton }
                .first { $0.title == "下一页 →" })
            XCTAssertTrue(next.emphasized)
            let anchor = CGPoint(x: previous.frame.minX + next.frame.midX, y: previous.frame.minY + next.frame.midY)
            let index = scheduler.durations.count
            XCTAssertTrue(next.accessibilityPerformPress())
            XCTAssertNil(controller.selectedID)
            scheduler.finish(index); scheduler.finish(index + 1)
            XCTAssertEqual(controller.layout?.anchor, anchor)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1400, height: 900).contains(try XCTUnwrap(controller.layout).frame))
            XCTAssertEqual(controller.viewModel.page?.slots.compactMap { $0 }.filter { $0.action == .previous }.count, 1)
            let child = try XCTUnwrap(controller.viewModel.page)
            let back = child.layout.items[try XCTUnwrap(child.slots.firstIndex { $0?.action == .previous })]
            let incoming = CGPoint(x: anchor.x - previous.center.x, y: anchor.y - previous.center.y)
            let outgoing = CGPoint(x: back.midX - child.layout.center.x, y: back.midY - child.layout.center.y)
            let scale = hypot(incoming.x, incoming.y) * hypot(outgoing.x, outgoing.y)
            XCTAssertEqual((incoming.x * outgoing.x + incoming.y * outgoing.y) / scale, -1, accuracy: 0.001)
            XCTAssertNil(controller.updateSelection(at: NSEvent.mouseLocation))
            ids += controller.pageNodes.compactMap(\.contentID)
            steps += 1
        }
        XCTAssertEqual(ids, snippets.map(\.id))
        XCTAssertFalse(controller.hasNextPage)
        for _ in 0..<steps {
            let current = try XCTUnwrap(controller.viewModel.page)
            let previous = current.layout.items[try XCTUnwrap(current.slots.firstIndex { $0?.action == .previous })]
            let index = scheduler.durations.count
            controller.returnToParent(); scheduler.finish(index); scheduler.finish(index + 1)
            XCTAssertEqual(controller.layout?.anchor, CGPoint(x: previous.midX, y: previous.midY))
            let restored = try XCTUnwrap(controller.viewModel.page)
            if let slot = restored.slots.firstIndex(where: { $0?.action == .previous }) {
                let back = restored.layout.items[slot]
                let incoming = CGPoint(x: previous.midX - current.layout.center.x, y: previous.midY - current.layout.center.y)
                let outgoing = CGPoint(x: back.midX - restored.layout.center.x, y: back.midY - restored.layout.center.y)
                XCTAssertEqual((incoming.x * outgoing.x + incoming.y * outgoing.y)
                    / (hypot(incoming.x, incoming.y) * hypot(outgoing.x, outgoing.y)), -1, accuracy: 0.001)
            }
        }
        XCTAssertEqual(controller.viewModel.page?.slots, root.slots)
        XCTAssertEqual(controller.viewModel.page?.remaining, root.remaining)
        XCTAssertEqual(controller.page, 0)
        XCTAssertEqual(controller.layout?.items.first?.midX, controller.layout?.center.x)
        XCTAssertGreaterThan(try XCTUnwrap(controller.layout?.items.first?.midY), try XCTUnwrap(controller.layout?.center.y))
        let view = try XCTUnwrap(controller.panel.contentView)
        try savePreview(view, name: "radial-next-page-node.png")
        let pending = scheduler.durations.count
        controller.enterNextPage(); controller.hide(); scheduler.finish(pending)
        XCTAssertFalse(controller.isPresented)
        XCTAssertTrue(controller.configure(profile: profile, at: CGPoint(x: 700, y: 450),
            visible: CGRect(x: 0, y: 0, width: 1400, height: 900)))
        _ = controller.viewModel.beginShow(initialMouse: .zero, requiresMovement: false)
        scheduler.finish(pending)
        XCTAssertEqual(controller.page, 0)
    }

    @MainActor
    func testNextPageHoverRequiresDwellAndDoesNotSelectSnippet() async throws {
        let scheduler = ManualAnimationScheduler()
        var mouse = CGPoint.zero
        let controller = FloatingMenuWindowController(animator: FloatingMenuAnimator(scheduler: scheduler), mouseLocation: { mouse })
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.hover", fallbackBundlePath: nil),
            displayName: "Test", buttons: (0..<13).map { Snippet(title: "文案 \($0)", text: "正文") })
        XCTAssertTrue(controller.configure(profile: profile, at: CGPoint(x: 700, y: 450),
            visible: CGRect(x: 0, y: 0, width: 1400, height: 900)))
        _ = controller.viewModel.beginShow(initialMouse: .zero, requiresMovement: false)
        let layout = try XCTUnwrap(controller.layout)
        let next = try XCTUnwrap((controller.panel.contentView as? FloatingMenuView)?.buttons.compactMap { $0 as? FloatingMenuButton }.first { $0.emphasized })
        let point = CGPoint(x: layout.frame.minX + next.frame.midX, y: layout.frame.minY + next.frame.midY)
        XCTAssertNil(controller.updateSelection(at: point))
        _ = controller.updateSelection(at: .zero)
        try await Task.sleep(for: .milliseconds(210))
        XCTAssertEqual(controller.page, 0)
        mouse = point
        XCTAssertNil(controller.updateSelection(at: point))
        XCTAssertTrue(controller.isInteractive(CGPoint(x: point.x - layout.frame.minX, y: point.y - layout.frame.minY)))
        for _ in 0..<100 where scheduler.durations.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(scheduler.durations.count, 1)
        guard scheduler.durations.count == 1 else { return }
        scheduler.finish(0); scheduler.finish(1)
        XCTAssertEqual(controller.page, 1)
        let view = try XCTUnwrap(controller.panel.contentView)
        let back = try XCTUnwrap((view as? FloatingMenuView)?.buttons.compactMap { $0 as? FloatingMenuButton }.first { $0.title == "← 上一页" })
        XCTAssertTrue(back.emphasized)
        try savePreview(view, name: "radial-next-page-return.png")
        controller.hide()
    }

    @MainActor
    func testBothModesUseOriginalRadialButtons() throws {
        let controller = FloatingMenuWindowController()
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.mode", fallbackBundlePath: nil),
            displayName: "Test", buttons: [Snippet(title: "测试", text: "正文")])
        var selections = 0
        controller.onSelect = { _ in selections += 1 }
        for mode in [MenuInteractionMode.hold, .persistent] {
            controller.interactionMode = mode
            XCTAssertTrue(controller.configure(profile: profile, at: CGPoint(x: 440, y: 280),
                visible: CGRect(x: 0, y: 0, width: 880, height: 560)))
            _ = controller.viewModel.beginShow(initialMouse: .zero, requiresMovement: false)
            let view = try XCTUnwrap(controller.panel.contentView as? FloatingMenuView)
            let button = try XCTUnwrap(view.buttons.first as? FloatingMenuButton)
            XCTAssertEqual(button.accessibilityPerformPress(), mode == .persistent)
        }
        XCTAssertEqual(selections, 1)
        controller.hide()
    }

    @MainActor
    func testNativeRadialAnimationAndPersistentClick() async throws {
        try requireVisibleUITests()
        let screen = try XCTUnwrap(NSScreen.main)
        let point = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        let controller = FloatingMenuWindowController(animator: FloatingMenuAnimator(reduceMotion: { false }))
        defer { controller.hide() }
        controller.interactionMode = .persistent
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.native.radial", fallbackBundlePath: nil),
            displayName: "Test", buttons: (0..<6).map { Snippet(title: "文案 \($0)", text: "正文") })
        XCTAssertTrue(controller.show(profile: profile, at: point))
        let view = try XCTUnwrap(controller.panel.contentView as? FloatingMenuView)
        let first = try XCTUnwrap(view.buttons.first)
        XCTAssertNotNil(view.animationLayer?.animation(forKey: "radialMotion"))
        var earlyChoice = false
        controller.onSelect = { _ in earlyChoice = true }
        first.performClick(nil)
        XCTAssertFalse(earlyChoice)
        try await Task.sleep(for: .milliseconds(60))
        let during = try XCTUnwrap(view.animationLayer?.presentation())
        XCTAssertLessThan(during.opacity, 1)
        XCTAssertGreaterThan(atan2(during.transform.m12, during.transform.m11), 0)
        XCTAssertLessThan(hypot(during.transform.m11, during.transform.m12), 1)
        let pivot = try XCTUnwrap(controller.layout).localCenter
        let shownPivot = during.convert(pivot, to: during.superlayer)
        XCTAssertEqual(shownPivot.x, pivot.x, accuracy: 0.05)
        XCTAssertEqual(shownPivot.y, pivot.y, accuracy: 0.05)
        try await Task.sleep(for: .milliseconds(420))
        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(view.animationLayer?.presentation()?.opacity ?? 0, 1, accuracy: 0.01)
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(view.animationLayer).transform))
        var chosen: UUID?
        controller.onSelect = { chosen = $0; controller.hide() }
        first.performClick(nil)
        XCTAssertEqual(chosen, profile.buttons[0].id)
        XCTAssertNotNil(view.animationLayer?.animation(forKey: "radialMotion"))
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertFalse(controller.panel.isVisible)
    }

    @MainActor
    func testStatusFitsShortAndWrappedMessages() throws {
        let status = InteractionStatusPanel()
        let short = status.content("读取超时，请重试。")
        XCTAssertLessThan(short.frame.width, 150)
        XCTAssertLessThan(short.frame.height, 40)
        try savePreview(short, name: "interaction-status-short.png")
        let long = status.content("当前输入框不支持直接写入，可在设置中开启粘贴插入。请调整后重新打开轮盘。")
        XCTAssertLessThanOrEqual(long.frame.width, 300)
        XCTAssertGreaterThan(long.frame.height, short.frame.height)
        try savePreview(long, name: "interaction-status-wrapped.png")
    }
    @MainActor
    func testFailureStatusAppearsBelowMouseAndFitsScreenEdges() {
        let safe = CGRect(x: -1400, y: -200, width: 1400, height: 900)
        let size = CGSize(width: 240, height: 48)
        let mouse = CGPoint(x: -700, y: 250)
        let frame = InteractionStatusPanel.frame(size: size, at: mouse, safe: safe)
        XCTAssertEqual(frame.midX, mouse.x)
        XCTAssertEqual(frame.maxY, mouse.y - 12)
        for point in [CGPoint(x: safe.minX, y: safe.minY), CGPoint(x: safe.maxX, y: safe.maxY)] {
            XCTAssertTrue(safe.contains(InteractionStatusPanel.frame(size: size, at: point, safe: safe)))
        }
    }
}
