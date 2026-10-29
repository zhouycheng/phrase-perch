import AppKit
import QuartzCore

@MainActor
final class FloatingMenuWindowController: NSObject, FloatingMenuPresenting {
    let panel: FloatingMenuPanel
    var onDismiss: (() -> Void)?
    var onSelect: ((UUID) -> Void)?
    var interactionMode = MenuInteractionMode.hold
    private(set) var page = 0
    private struct NavigationFrame {
        let group: UUID?
        let content: RadialPage
        let page: Int
    }
    private var profile: AppProfile?
    private var visible = CGRect.zero
    private(set) var currentGroup: UUID?
    private var parents: [NavigationFrame] = []
    private var pendingNavigation: NavigationFrame?
    private var hoverTask: Task<Void, Never>?
    private var hoverNode: RadialNode.Action?
    private var generation = 0
    private var changingPage = false
    var hasNextPage: Bool { viewModel.page?.hasNext == true }
    var pageNodes: [RadialNode] { viewModel.page.map { Array($0.remaining.prefix($0.consumed)) } ?? [] }
    private let statusPanel = InteractionStatusPanel()
    let viewModel = FloatingMenuViewModel()
    var titleCharacterLimit = 10
    var menuAppearance = MenuAppearance.matte
    private let menuView = FloatingMenuView(frame: .zero)
    private let mouseLocation: () -> CGPoint
    private let animator: FloatingMenuAnimator
    var layout: RadialLayout? { viewModel.layout }
    var selectedID: UUID? { changingPage ? nil : viewModel.selectedID }
    var failureMessage: String { viewModel.failureMessage }
    private var globalMotion: Any?
    private var localMotion: Any?
    var isPresented: Bool { viewModel.isPresented }
    var frame: CGRect { panel.frame }

    init(
        animator: FloatingMenuAnimator = FloatingMenuAnimator(),
        mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.animator = animator
        self.mouseLocation = mouseLocation
        panel = FloatingMenuPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("径向快捷内容菜单")
        menuView.onSelect = { [weak self] action in
            guard let self, isPresented, !changingPage else { return }
            activate(action)
        }
    }
    private func activate(_ action: RadialNode.Action) {
        switch action {
        case .next: enterNextPage()
        case .previous: returnToParent()
        case .group(let id): enterGroup(id)
        case .content(let id): if interactionMode == .persistent { onSelect?(id) }
        }
    }

    func showStatus(_ message: String, at point: CGPoint) {
        statusPanel.show(message, at: point)
    }
    // Also used by the offscreen native rendering check, without opening a window or requiring AX permissions.
    @discardableResult
    func configure(profile: AppProfile, at point: CGPoint, visible: CGRect) -> Bool {
        guard viewModel.configure(profile: profile, at: point, visible: visible, characterLimit: titleCharacterLimit) else { return false }
        self.profile = profile
        self.visible = visible
        currentGroup = nil
        parents = []
        pendingNavigation = nil
        cancelHover()
        generation += 1
        animator.cancel()
        changingPage = false
        page = 0
        menuView.layer?.removeAllAnimations()
        menuView.layer?.opacity = 1
        panel.isMovableByWindowBackground = false
        panel.title = "PhrasePerch — 径向菜单"
        panel.setAccessibilityLabel("径向快捷内容菜单")
        render()
        return true
    }
    @discardableResult
    func show(
        profile: AppProfile, at point: CGPoint, initialMouse: CGPoint? = nil,
        requiresMovement: Bool = false
    ) -> Bool {
        removeMotionObservers()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return false }
        guard configure(profile: profile, at: point, visible: screen.visibleFrame), let layout else { return false }
        let token = viewModel.beginShow(initialMouse: initialMouse ?? point, requiresMovement: requiresMovement)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        animator.animate(layer: menuView.animationLayer, layout: layout, expanding: true) { [weak self] in
            guard let self, self.viewModel.finishShow(token) else { return }
            self.updateSelection(at: NSEvent.mouseLocation)
        }
        panel.orderFrontRegardless()
        installMotionObservers()
        CATransaction.flush()
        updateSelection(at: NSEvent.mouseLocation)
        return true
    }
    func hide() {
        cancelHover()
        if let pendingNavigation {
            restore(pendingNavigation)
            _ = parents.popLast()
            self.pendingNavigation = nil
        }
        generation += 1
        changingPage = false
        animator.cancel()
        let token = viewModel.beginHide()
        panel.ignoresMouseEvents = true
        removeMotionObservers()
        guard panel.isVisible, let layout else {
            animator.cancel()
            _ = viewModel.finishHide(token)
            return
        }
        collapseForClose(token: token, generation: generation, layout: layout)
    }
    private func collapseForClose(token: Int, generation expected: Int, layout: RadialLayout) {
        animator.animate(layer: menuView.animationLayer, layout: layout, expanding: false) { [weak self] in
            guard let self, generation == expected else { return }
            if let parent = parents.popLast() {
                restore(parent)
                render()
                collapseForClose(token: token, generation: expected, layout: parent.content.layout)
            } else if viewModel.finishHide(token) { panel.orderOut(nil) }
        }
    }

    func isInteractive(_ point: CGPoint) -> Bool { menuView.interactiveIndex(point) != nil }
    func enterNextPage() {
        guard let content = viewModel.page, content.hasNext else { return }
        navigate(.next, nodes: Array(content.remaining.dropFirst(content.consumed)), group: currentGroup, page: page + 1)
    }
    private func navigate(_ action: RadialNode.Action, nodes: [RadialNode], group: UUID?, page: Int) {
        guard isPresented, !changingPage, let content = viewModel.page,
            let slot = content.slots.firstIndex(where: { $0?.action == action }) else { return }
        let saved = NavigationFrame(group: currentGroup, content: content, page: self.page)
        let item = content.layout.items[slot]
        let nodeCenter = CGPoint(x: item.midX, y: item.midY)
        guard viewModel.configure(nodes: nodes, at: nodeCenter, visible: visible,
            hasPrevious: true, previousAngle: atan2(content.layout.center.x - nodeCenter.x,
                content.layout.center.y - nodeCenter.y), characterLimit: titleCharacterLimit) else {
            cancelHover()
            showStatus(viewModel.failureMessage, at: NSEvent.mouseLocation)
            return
        }
        parents.append(saved)
        pendingNavigation = saved
        currentGroup = group
        self.page = page
        beginNavigation()
        let token = generation
        animator.animate(layer: menuView.animationLayer, layout: saved.content.layout, expanding: false) { [weak self] in
            guard let self, generation == token, isPresented else { return }
            pendingNavigation = nil
            render()
            expandNavigation()
        }
    }
    @discardableResult
    func updateSelection(at screenPoint: CGPoint) -> UUID? {
        guard !changingPage else { cancelHover(); return nil }
        guard let layout else { return nil }
        let local = CGPoint(x: screenPoint.x - layout.frame.minX, y: screenPoint.y - layout.frame.minY)
        let index = menuView.interactiveIndex(local)
        let node = index.flatMap { menuView.node(at: $0) }
        _ = viewModel.select(at: screenPoint, hitID: node?.contentID)
        menuView.showSelection(viewModel.acceptsHover ? index : nil)
        let navigation = viewModel.acceptsHover && node?.isNavigation == true ? node?.action : nil
        scheduleHover(navigation)
        panel.ignoresMouseEvents = !isPresented
        return selectedID
    }
    private func cancelHover() {
        hoverTask?.cancel(); hoverTask = nil; hoverNode = nil
    }
    private func scheduleHover(_ id: RadialNode.Action?) {
        guard id != hoverNode else { return }
        cancelHover()
        guard let id, isPresented else { return }
        hoverNode = id
        let token = generation
        hoverTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let self, generation == token, hoverNode == id, isPresented else { return }
            updateSelection(at: mouseLocation())
            guard hoverNode == id else { return }
            activate(id)
        }
    }
    func enterGroup(_ id: UUID) {
        guard let profile else { return }
        navigate(.group(id), nodes: RadialNode.contents(profile: profile, group: id), group: id, page: 0)
    }
    func returnToParent() {
        guard isPresented, !changingPage, let parent = parents.last, let layout,
            let slot = viewModel.page?.slots.firstIndex(where: { $0?.action == .previous }) else { return }
        let item = layout.items[slot]
        let point = CGPoint(x: item.midX, y: item.midY)
        guard let restored = parent.content.relocated(at: point, visible: visible,
            previousAngle: atan2(layout.center.x - point.x, layout.center.y - point.y)) else {
            cancelHover()
            showStatus("当前屏幕空间不足，无法展示轮盘。", at: NSEvent.mouseLocation)
            return
        }
        beginNavigation()
        let token = generation
        animator.animate(layer: menuView.animationLayer, layout: layout, expanding: false) { [weak self] in
            guard let self, generation == token, isPresented else { return }
            _ = parents.popLast()
            currentGroup = parent.group; page = parent.page
            viewModel.restore(restored)
            render()
            expandNavigation(direction: .backward)
        }
    }
    private func restore(_ parent: NavigationFrame) {
        currentGroup = parent.group; page = parent.page
        viewModel.restore(parent.content)
    }
    private func beginNavigation() {
        cancelHover()
        generation += 1
        changingPage = true
        viewModel.resetSelection(at: NSEvent.mouseLocation)
        menuView.showSelection(nil)
        animator.cancel()
    }
    private func expandNavigation(direction: FloatingMenuAnimationConfiguration.Direction = .forward) {
        guard let layout else { return }
        let token = generation
        viewModel.resetSelection(at: NSEvent.mouseLocation)
        changingPage = false
        animator.animate(layer: menuView.animationLayer, layout: layout, expanding: true, direction: direction) { [weak self] in
            guard let self, generation == token, isPresented else { return }
            self.updateSelection(at: NSEvent.mouseLocation)
        }
    }
    private func installMotionObservers() {
        removeMotionObservers()
        globalMotion = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updateSelection(at: NSEvent.mouseLocation)
        }
        localMotion = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited, .leftMouseDragged]) { [weak self] event in
            self?.updateSelection(at: NSEvent.mouseLocation)
            return event
        }
    }

    private func removeMotionObservers() {
        if let globalMotion { NSEvent.removeMonitor(globalMotion) }
        if let localMotion { NSEvent.removeMonitor(localMotion) }
        globalMotion = nil
        localMotion = nil
    }
    private func render() {
        guard let layout else { return }
        panel.setFrame(layout.frame, display: false)
        menuView.allowsClick = interactionMode == .persistent
        menuView.configure(slots: viewModel.page?.slots ?? [], layout: layout, titles: viewModel.page?.titles, appearance: menuAppearance)
        panel.contentView = menuView
    }
    @objc private func dismiss() { if isPresented { onDismiss?() } }
}
