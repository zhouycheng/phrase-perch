import AppKit
import QuartzCore

struct RadialLayout {
    let frame: CGRect
    let anchor: CGPoint // Animation origin, never clamped.
    let center: CGPoint // Symmetric ring center, translated as one group at edges.
    let items: [CGRect]
    static let buttonSize = CGSize(width: 88, height: 40)

    init?(anchor: CGPoint, visible: CGRect, count: Int) {
        guard count > 0, count <= 512, anchor.x.isFinite, anchor.y.isFinite,
              visible.contains(anchor), visible.width >= 104, visible.height >= 56 else { return nil }
        let safe = visible.insetBy(dx: 8, dy: 8)
        // Leave a half-point inside the safety margin so fractional trigonometric
        // coordinates remain contained after translation on negative-coordinate displays.
        let fitting = safe.insetBy(dx: 0.5, dy: 0.5)
        var placed: [CGRect] = [], radius: CGFloat = 100, ringNumber = 1
        while placed.count < count {
            let slots = min(count - placed.count, ringNumber * 6)
            var ring: [CGRect] = []
            while radius * 2 <= max(safe.width, safe.height) + 100 {
                ring = (0..<slots).map { index in
                    let angle = CGFloat.pi / 2 - CGFloat(index) * 2 * .pi / CGFloat(slots)
                    return CGRect(x: cos(angle) * radius - Self.buttonSize.width / 2,
                                  y: sin(angle) * radius - Self.buttonSize.height / 2,
                                  width: Self.buttonSize.width, height: Self.buttonSize.height)
                }
                let all = placed + ring
                let collides = all.enumerated().contains { index, rect in
                    all.dropFirst(index + 1).contains { rect.insetBy(dx: -6, dy: -6).intersects($0) }
                }
                if !collides { break }
                radius += 12
            }
            guard !ring.isEmpty, !ring.enumerated().contains(where: { index, rect in
                (placed + Array(ring.dropFirst(index + 1))).contains { rect.insetBy(dx: -6, dy: -6).intersects($0) }
            }) else { return nil }
            placed += ring
            let bounds = placed.reduce(CGRect(x: -16, y: -16, width: 32, height: 32)) { $0.union($1) }
            guard bounds.width <= fitting.width, bounds.height <= fitting.height else { return nil }
            radius += 72; ringNumber += 1
        }
        let bounds = placed.reduce(CGRect(x: -16, y: -16, width: 32, height: 32)) { $0.union($1) }
        let center = CGPoint(x: max(fitting.minX - bounds.minX, min(anchor.x, fitting.maxX - bounds.maxX)),
                             y: max(fitting.minY - bounds.minY, min(anchor.y, fitting.maxY - bounds.maxY)))
        let translated = placed.map { $0.offsetBy(dx: center.x, dy: center.y) }
        guard translated.allSatisfy(safe.contains) else { return nil }
        var windowBounds = CGRect(x: anchor.x, y: anchor.y, width: 1, height: 1)
        for rect in translated { windowBounds = windowBounds.union(rect) }
        frame = windowBounds.insetBy(dx: -8, dy: -8).intersection(visible)
        self.anchor = anchor; self.center = center; items = translated
    }
    var localAnchor: CGPoint { CGPoint(x: anchor.x - frame.minX, y: anchor.y - frame.minY) }
    func itemRect(index: Int) -> CGRect { items[index].offsetBy(dx: -frame.minX, dy: -frame.minY) }
    func selectedIndex(at point: CGPoint) -> Int? {
        items.firstIndex { CGPath(roundedRect: $0, cornerWidth: 12, cornerHeight: 12, transform: nil).contains(point) }
    }
}

struct SelectionMovement {
    let initialMouse: CGPoint
    let requiresMovement: Bool
    private(set) var armed = false
    mutating func update(_ point: CGPoint) -> Bool {
        if !requiresMovement || hypot(point.x - initialMouse.x, point.y - initialMouse.y) > 3 { armed = true }
        return armed
    }
}

struct VisibleOverlay {
    var ownerPID: pid_t
    var layer: Int
    var frame: CGRect
    var alpha: Double
}

func hasForeignOverlay(_ windows: [VisibleOverlay], ownPID: pid_t, targetPID: pid_t? = nil,
                       menuFrame: CGRect, screens: [CGRect] = []) -> Bool {
    windows.contains { $0.ownerPID != ownPID && $0.ownerPID != targetPID && $0.layer > 0 && $0.alpha > 0.05 &&
        $0.frame.width >= 48 && $0.frame.height >= 48 && $0.frame.intersects(menuFrame) &&
        !screens.contains(where: $0.frame.contains) }
}

// The same epoch guards animation completion and interaction; a cancelled fade cannot hide a new menu.
struct MenuPresentation {
    enum Phase { case hidden, showing, visible, hiding }
    private(set) var generation = 0
    private(set) var phase = Phase.hidden
    var presented: Bool { phase == .showing || phase == .visible }
    mutating func show() -> Int { generation += 1; phase = .showing; return generation }
    mutating func hide() -> Int { generation += 1; phase = .hiding; return generation }
    mutating func finishShow(_ token: Int) -> Bool {
        guard token == generation, phase == .showing else { return false }
        phase = .visible; return true
    }
    mutating func finishHide(_ token: Int) -> Bool {
        guard token == generation, phase == .hiding else { return false }
        phase = .hidden; return true
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
class FloatingButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
}
final class RadialButton: FloatingButton {
    var selected = false { didSet { needsDisplay = true } }
    override func mouseDown(with event: NSEvent) { } // Release of the trigger commits, never a click.
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        (selected ? NSColor.controlAccentColor : NSColor(calibratedWhite: 0.09, alpha: 0.97)).setFill()
        shape.fill()
        NSColor.white.withAlphaComponent(selected ? 0.6 : 0.18).setStroke()
        shape.lineWidth = selected ? 1.5 : 0.8; shape.stroke()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                  withAttributes: attributes)
    }
}

@MainActor
final class FloatingPanelController: NSObject {
    let panel: FloatingPanel
    var onDismiss: (() -> Void)?
    private var movement = SelectionMovement(initialMouse: .zero, requiresMovement: false)
    private var snippets: [Snippet] = []
    private(set) var layout: RadialLayout?
    private(set) var selectedID: UUID?
    private(set) var failureMessage = ""
    private var buttons: [NSButton] = []
    private var presentation = MenuPresentation()
    private var globalMotion: Any?
    private var localMotion: Any?
    private var overlayWatch: Timer?
    var isPresented: Bool { presentation.presented }

    override init() {
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("径向文案菜单")
    }
    // Also used by the offscreen native rendering check, without opening a window or requiring AX permissions.
    @discardableResult
    func configure(profile: AppProfile, at point: CGPoint, visible: CGRect) -> Bool {
        let enabled = profile.buttons.filter(\.isEnabled)
        guard let next = RadialLayout(anchor: point, visible: visible, count: enabled.count) else {
            failureMessage = "文案无法完整排入当前屏幕，请减少启用文案数量。"; return false
        }
        panel.isMovableByWindowBackground = false
        panel.title = "PhrasePerch — 径向菜单"
        panel.setAccessibilityLabel("径向文案菜单")
        snippets = enabled; layout = next; selectedID = nil; failureMessage = ""
        render()
        return true
    }
    @discardableResult
    func show(profile: AppProfile, at point: CGPoint, initialMouse: CGPoint? = nil,
              requiresMovement: Bool = false) -> Bool {
        removeMotionObservers()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main,
              configure(profile: profile, at: point, visible: screen.visibleFrame), let layout else { return false }
        guard !foreignOverlayVisible(frame: layout.frame) else {
            failureMessage = "其他悬浮窗口占用了菜单区域，请关闭后重试。"; return false
        }
        movement = SelectionMovement(initialMouse: initialMouse ?? point, requiresMovement: requiresMovement)
        let token = presentation.show()
        panel.alphaValue = 1; panel.ignoresMouseEvents = true
        animateButtons(expanding: true)
        panel.orderFrontRegardless(); installMotionObservers()
        CATransaction.flush()
        updateSelection(at: NSEvent.mouseLocation)
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration(expanding: true)) { [weak self] in
            guard let self, self.presentation.finishShow(token) else { return }
            self.updateSelection(at: NSEvent.mouseLocation)
        }
        return true
    }
    func hide() {
        let token = presentation.hide()
        panel.ignoresMouseEvents = true; selectedID = nil
        removeMotionObservers()
        guard panel.isVisible else { _ = presentation.finishHide(token); return }
        animateButtons(expanding: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration(expanding: false)) { [weak self] in
            guard let self, self.presentation.finishHide(token) else { return }
            self.panel.orderOut(nil)
        }
    }
    private func animationDuration(expanding: Bool) -> Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : (expanding ? 0.18 : 0.12)
    }
    private func animateButtons(expanding: Bool) {
        guard let layout else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for button in buttons {
            guard let layer = button.layer else { continue }
            var collapsed = CATransform3DMakeScale(0.2, 0.2, 1)
            collapsed.m41 = layout.localAnchor.x - button.frame.midX
            collapsed.m42 = layout.localAnchor.y - button.frame.midY
            if reduced { collapsed = CATransform3DIdentity }
            // Keep AppKit's layer position untouched. Transform and opacity share one clock.
            let current = layer.presentation()?.transform ?? layer.transform
            let opacity = layer.presentation()?.opacity ?? layer.opacity
            let destination = expanding ? CATransform3DIdentity : collapsed
            layer.removeAllAnimations()
            layer.transform = destination; layer.opacity = expanding ? 1 : 0
            let motion = CABasicAnimation(keyPath: "transform")
            motion.fromValue = NSValue(caTransform3D: expanding ? collapsed : current)
            motion.toValue = NSValue(caTransform3D: destination)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = expanding ? 0 : opacity; fade.toValue = expanding ? 1 : 0
            let group = CAAnimationGroup(); group.animations = [motion, fade]
            group.duration = animationDuration(expanding: expanding)
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            layer.add(group, forKey: "radialMotion")
        }
        CATransaction.commit()
    }
    private func interactiveIndex(_ local: CGPoint) -> Int? {
        buttons.firstIndex { button in
            guard let layer = button.layer else { return false }
            let shown = layer.presentation() ?? layer
            guard shown.opacity > 0.05 else { return false }
            let rect = shown.frame
            let scale = min(rect.width / RadialLayout.buttonSize.width, rect.height / RadialLayout.buttonSize.height)
            return CGPath(roundedRect: rect, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil).contains(local)
        }
    }
    func isInteractive(_ point: CGPoint) -> Bool { interactiveIndex(point) != nil }
    @discardableResult
    func updateSelection(at screenPoint: CGPoint) -> UUID? {
        guard isPresented, let layout else { selectedID = nil; return nil }
        let local = CGPoint(x: screenPoint.x - layout.frame.minX, y: screenPoint.y - layout.frame.minY)
        let index = movement.update(screenPoint) ? interactiveIndex(local) : nil
        selectedID = index.map { snippets[$0].id }
        for (slot, button) in buttons.enumerated() { (button as? RadialButton)?.selected = slot == index }
        panel.ignoresMouseEvents = !isPresented || interactiveIndex(local) == nil
        return selectedID
    }
    private func installMotionObservers() {
        removeMotionObservers()
        // Peer overlays remain metadata-only observations; no other app's events are intercepted.
        overlayWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPresented, self.foreignOverlayVisible(frame: self.panel.frame) else { return }
                self.dismissForForeignActivity()
            }
        }
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
        overlayWatch?.invalidate(); overlayWatch = nil
        globalMotion = nil; localMotion = nil
    }
    private func dismissForForeignActivity() {
        if let onDismiss { onDismiss() } else { hide() }
    }
    private func foreignOverlayVisible(frame: CGRect) -> Bool {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let windows = raw.compactMap { entry -> VisibleOverlay? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let level = entry[kCGWindowLayer as String] as? Int,
                  let alpha = entry[kCGWindowAlpha as String] as? Double,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return VisibleOverlay(ownerPID: pid, layer: level,
                frame: CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height), alpha: alpha)
        }
        return hasForeignOverlay(windows, ownPID: getpid(),
            targetPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            menuFrame: frame, screens: NSScreen.screens.map(\.frame))
    }
    private func render() {
        guard let layout else { return }
        panel.setFrame(layout.frame, display: false)
        let root = NSView(frame: CGRect(origin: .zero, size: layout.frame.size)); root.wantsLayer = true
        root.appearance = NSAppearance(named: .darkAqua)
        buttons = []
        for index in snippets.indices {
            let rect = layout.itemRect(index: index)
            let button = RadialButton(frame: rect)
            button.wantsLayer = true; button.isBordered = false; button.focusRingType = .none
            button.title = floatingButtonTitle(snippets[index].title)
            button.setAccessibilityLabel(snippets[index].title)
            button.toolTip = String(snippets[index].text.prefix(180))
            buttons.append(button); root.addSubview(button)
        }
        // The empty center is the cancellation area; it neither receives focus nor blocks the editor.
        panel.contentView = root
    }
    @objc private func dismiss() { if isPresented { onDismiss?() } }
}

// A native file drag, not an image or path string; AppKit uses the dragging pasteboard.
final class ApplicationDragView: NSView, NSDraggingSource {
    let applicationURL: URL
    private let applicationIcon: NSImage
    private let iconView = NSImageView(frame: .zero)
    private let nameLabel = NSTextField(labelWithString: "PhrasePerch")
    private let statusLabel = NSTextField(labelWithString: "拖入系统授权列表")
    var onDragEnded: ((Bool) -> Void)?
    init(applicationURL: URL, frame: CGRect) {
        self.applicationURL = applicationURL
        applicationIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        iconView.image = applicationIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = CGRect(x: 8, y: 6, width: 32, height: 32)
        addSubview(iconView)
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.frame = CGRect(x: 48, y: 3, width: frame.width - 58, height: 18)
        addSubview(nameLabel)
        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.frame = CGRect(x: 48, y: 22, width: frame.width - 58, height: 15)
        addSubview(statusLabel)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
        setAccessibilityLabel("将 PhrasePerch 拖入系统授权列表")
        setAccessibilityHelp("拖动此行到系统设置的系统授权列表，然后开启 PhrasePerch")
        toolTip = "拖动此行到系统授权列表，然后开启 PhrasePerch"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        NSCursor.openHand.set()
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        NSCursor.arrow.set()
    }
    func draggingItem() -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: applicationURL as NSURL)
        item.setDraggingFrame(iconView.frame, contents: applicationIcon)
        return item
    }
    override func mouseDragged(with event: NSEvent) {
        beginDraggingSession(with: [draggingItem()], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finishDrag(operation: operation)
    }
    func finishDrag(operation: NSDragOperation) { onDragEnded?(operation.contains(.copy)) }
    func updateStatus(_ text: String, color: NSColor = .secondaryLabelColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
        statusLabel.toolTip = text
    }
}

final class AuthorizationBackdrop: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

func authorizationGuideFrame(settings: CGRect?, visible: CGRect) -> CGRect {
    // ponytail: without AX, use window bounds; place below the window or at its bottom, and allow manual adjustment.
    let width = min(420, settings.map { max(300, $0.width * 0.68 - 28) } ?? 420, visible.width)
    let size = CGSize(width: width, height: min(112, visible.height))
    let x = settings.map { $0.maxX - width - 14 } ?? visible.maxX - width - 16
    let y = settings.map { $0.minY - size.height - 8 >= visible.minY
        ? $0.minY - size.height - 8 : $0.minY + 12 } ?? visible.minY + 16
    return CGRect(x: max(visible.minX, min(x, visible.maxX - size.width)),
                  y: max(visible.minY, min(y, visible.maxY - size.height)), width: size.width, height: size.height)
}


@MainActor
final class AuthorizationGuideController: NSObject {
    let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    var onDragEnded: ((Bool) -> Void)?
    private var followTimer: Timer?
    private var previousSettingsFrame: CGRect?
    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        panel.title = "PhrasePerch — 授权拖拽"
        panel.setAccessibilityLabel("PhrasePerch 授权拖拽")
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    func configure(applicationURL: URL, frame: CGRect) {
        panel.setFrame(frame, display: false)
        let root = AuthorizationBackdrop(frame: CGRect(origin: .zero, size: frame.size))
        root.material = .popover; root.state = .active; root.blendingMode = .behindWindow
        root.appearance = NSAppearance(named: .darkAqua)
        root.wantsLayer = true; root.layer?.cornerRadius = 14; root.layer?.masksToBounds = true
        let label = NSTextField(wrappingLabelWithString: "将下方应用拖入授权列表，然后开启开关。")
        label.frame = CGRect(x: 16, y: 66, width: frame.width - 52, height: 32)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        root.addSubview(label)
        let drag = ApplicationDragView(applicationURL: applicationURL,
                                       frame: CGRect(x: 16, y: 12, width: frame.width - 32, height: 44))
        drag.onDragEnded = { [weak self] accepted in
            if accepted { self?.hide() }
            self?.onDragEnded?(accepted)
        }
        root.addSubview(drag)
        let close = FloatingButton(frame: CGRect(x: frame.width - 28, y: 80, width: 18, height: 20))
        close.title = "×"; close.isBordered = false; close.target = self; close.action = #selector(hide)
        close.setAccessibilityLabel("关闭拖拽提示")
        root.addSubview(close)
        panel.contentView = root
    }
    func show(applicationURL: URL) {
        hide()
        let settings = settingsWindowFrame()
        let point = settings.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        configure(applicationURL: applicationURL,
                  frame: authorizationGuideFrame(settings: settings, visible: screen.visibleFrame))
        previousSettingsFrame = settings
        panel.orderFrontRegardless()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible, let frame = self.settingsWindowFrame() else { return }
                defer { self.previousSettingsFrame = frame }
                guard let previous = self.previousSettingsFrame, frame.origin != previous.origin,
                      let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else { return }
                let translated = self.panel.frame.offsetBy(dx: frame.minX - previous.minX, dy: frame.minY - previous.minY)
                self.panel.setFrameOrigin(CGPoint(x: max(screen.visibleFrame.minX, min(translated.minX, screen.visibleFrame.maxX - translated.width)),
                                                 y: max(screen.visibleFrame.minY, min(translated.minY, screen.visibleFrame.maxY - translated.height))))
            }
        }
    }
    @objc func hide() {
        followTimer?.invalidate(); followTimer = nil
        panel.orderOut(nil)
    }
    private func settingsWindowFrame() -> CGRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let entry = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid &&
                  ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
}
