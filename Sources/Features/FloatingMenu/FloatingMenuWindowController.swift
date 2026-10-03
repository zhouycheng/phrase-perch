import AppKit
import QuartzCore

@MainActor
final class FloatingMenuWindowController: NSObject, FloatingMenuPresenting {
    let panel: FloatingMenuPanel
    var onDismiss: (() -> Void)?
    let viewModel = FloatingMenuViewModel()
    private let menuView = FloatingMenuView(frame: .zero)
    private let overlayInspector: any OverlayInspecting
    private let animator: FloatingMenuAnimator
    var layout: RadialLayout? { viewModel.layout }
    var selectedID: UUID? { viewModel.selectedID }
    var failureMessage: String { viewModel.failureMessage }
    private var globalMotion: Any?
    private var localMotion: Any?
    private var overlayWatch: Timer?
    var isPresented: Bool { viewModel.isPresented }
    var frame: CGRect { panel.frame }

    init(
        animator: FloatingMenuAnimator = FloatingMenuAnimator(),
        overlayInspector: any OverlayInspecting = MacOverlayInspector()
    ) {
        self.overlayInspector = overlayInspector
        self.animator = animator
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
        panel.setAccessibilityLabel("径向文案菜单")
    }
    // Also used by the offscreen native rendering check, without opening a window or requiring AX permissions.
    @discardableResult
    func configure(profile: AppProfile, at point: CGPoint, visible: CGRect) -> Bool {
        guard viewModel.configure(profile: profile, at: point, visible: visible) else { return false }
        panel.isMovableByWindowBackground = false
        panel.title = "PhrasePerch — 径向菜单"
        panel.setAccessibilityLabel("径向文案菜单")
        render()
        return true
    }
    @discardableResult
    func show(
        profile: AppProfile, at point: CGPoint, initialMouse: CGPoint? = nil,
        requiresMovement: Bool = false
    ) -> Bool {
        removeMotionObservers()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main,
            configure(profile: profile, at: point, visible: screen.visibleFrame), let layout
        else { return false }
        guard !overlayInspector.hasOverlay(in: layout.frame) else {
            viewModel.fail("其他悬浮窗口占用了菜单区域，请关闭后重试。")
            return false
        }
        let token = viewModel.beginShow(initialMouse: initialMouse ?? point, requiresMovement: requiresMovement)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = true
        animator.animate(buttons: menuView.buttons, layout: layout, expanding: true) { [weak self] in
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
        let token = viewModel.beginHide()
        panel.ignoresMouseEvents = true
        removeMotionObservers()
        guard panel.isVisible, let layout else {
            animator.cancel()
            _ = viewModel.finishHide(token)
            return
        }
        animator.animate(buttons: menuView.buttons, layout: layout, expanding: false) { [weak self] in
            guard let self, self.viewModel.finishHide(token) else { return }
            self.panel.orderOut(nil)
        }
    }
    func isInteractive(_ point: CGPoint) -> Bool { menuView.interactiveIndex(point) != nil }
    @discardableResult
    func updateSelection(at screenPoint: CGPoint) -> UUID? {
        guard let layout else { return nil }
        let local = CGPoint(x: screenPoint.x - layout.frame.minX, y: screenPoint.y - layout.frame.minY)
        let index = menuView.interactiveIndex(local)
        let hitID = index.map { viewModel.snippets[$0].id }
        let selected = viewModel.select(at: screenPoint, hitID: hitID)
        menuView.showSelection(selected.flatMap { id in viewModel.snippets.firstIndex { $0.id == id } })
        panel.ignoresMouseEvents = !isPresented || index == nil
        return selected
    }
    private func installMotionObservers() {
        removeMotionObservers()
        // Peer overlays remain metadata-only observations; no other app's events are intercepted.
        overlayWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPresented, self.overlayInspector.hasOverlay(in: self.panel.frame) else { return }
                self.dismissForForeignActivity()
            }
        }
        globalMotion = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updateSelection(at: NSEvent.mouseLocation)
        }
        localMotion = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .mouseEntered, .mouseExited, .leftMouseDragged,
        ]) { [weak self] event in
            self?.updateSelection(at: NSEvent.mouseLocation)
            return event
        }
    }
    private func removeMotionObservers() {
        if let globalMotion { NSEvent.removeMonitor(globalMotion) }
        if let localMotion { NSEvent.removeMonitor(localMotion) }
        overlayWatch?.invalidate()
        overlayWatch = nil
        globalMotion = nil
        localMotion = nil
    }
    private func dismissForForeignActivity() {
        if let onDismiss { onDismiss() } else { hide() }
    }
    private func render() {
        guard let layout else { return }
        panel.setFrame(layout.frame, display: false)
        menuView.configure(snippets: viewModel.snippets, layout: layout)
        panel.contentView = menuView
    }
    @objc private func dismiss() { if isPresented { onDismiss?() } }
}
