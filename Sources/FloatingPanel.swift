import AppKit
import QuartzCore

struct PillLayout {
    let frame: CGRect
    let bar: CGRect
    let itemWidth: CGFloat
    let below: Bool
    var center: CGPoint { CGPoint(x: bar.midX, y: bar.midY) }
    var shape: CGPath { CGPath(roundedRect: bar, cornerWidth: 24, cornerHeight: 24, transform: nil) }
    var closeFrame: CGRect { CGRect(x: bar.maxX - 42, y: bar.midY - 12, width: 24, height: 24) }

    init(anchor: CGPoint, visible: CGRect, count: Int) {
        let count = max(1, min(count, 6))
        itemWidth = min(72, max(1, (visible.width - 84) / CGFloat(count)))
        let width = CGFloat(count) * itemWidth + 72, height: CGFloat = 72
        bar = CGRect(x: 6, y: 20, width: width - 12, height: 48)
        below = anchor.y + 16 + height > visible.maxY
        let y = below ? anchor.y - 16 - height : anchor.y + 16
        frame = CGRect(x: max(visible.minX, min(anchor.x - width / 2, visible.maxX - width)),
                       y: max(visible.minY, min(y, visible.maxY - height)), width: width, height: height)
    }
    func itemRect(index: Int) -> CGRect {
        CGRect(x: bar.minX + 12 + CGFloat(index) * itemWidth, y: bar.minY + 6, width: itemWidth, height: 36)
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

func pressedNewModifier(previous: UInt, current: UInt) -> Bool {
    let mask = UInt(CGEventFlags([.maskCommand, .maskAlternate, .maskShift, .maskControl]).rawValue)
    return current & ~previous & mask != 0
}

final class PillBackdrop: NSView {
    var shape: CGPath = CGMutablePath()
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.addPath(shape); context.clip()
        NSGradient(starting: NSColor(calibratedWhite: 0.045, alpha: 0.97),
                   ending: NSColor(calibratedWhite: 0.02, alpha: 0.97))?.draw(in: bounds, angle: -45)
        context.restoreGState()
        context.addPath(shape); context.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        context.setLineWidth(0.8); context.strokePath()
    }
}

func snippetPage(count: Int, page: Int) -> Range<Int> {
    let pages = max(1, (count + 4) / 5), start = min(max(0, page), pages - 1) * 5
    return start..<min(start + 5, count)
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
final class PillButton: FloatingButton {
    override var isFlipped: Bool { false }
    var shape: CGPath = CGMutablePath()
    var labelCenter = CGPoint.zero
    private var hovered = false
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return shape.contains(local) ? self : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseMoved(with event: NSEvent) { updateHover(convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { updateHover(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    private func updateHover(_ point: CGPoint) { hovered = shape.contains(point); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if hovered && isEnabled {
            context.addPath(shape)
            context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor)
            context.fillPath()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: labelCenter.x - size.width / 2, y: labelCenter.y - size.height / 2),
                                  withAttributes: attributes)
    }
}

// A native file drag, not an image or path string; AppKit uses the dragging pasteboard.
final class ApplicationDragView: NSImageView, NSDraggingSource {
    let applicationURL: URL
    var onDragEnded: ((Bool) -> Void)?
    init(applicationURL: URL, frame: CGRect) {
        self.applicationURL = applicationURL
        super.init(frame: frame)
        image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityLabel("拖动 PhrasePerch 应用到系统授权列表")
        toolTip = "拖入应用列表，然后开启 PhrasePerch 开关"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { }
    func draggingItem() -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: applicationURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
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
}

final class DragInstructionView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let arrow = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemBlue]))
        arrow?.draw(in: bounds.insetBy(dx: 2, dy: 2))
    }
    func animateHand() {
        wantsLayer = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let travel = CABasicAnimation(keyPath: "transform.translation.y")
        travel.fromValue = 0; travel.toValue = 4
        travel.duration = 0.8; travel.autoreverses = true; travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(travel, forKey: "dragDirection")
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
final class FloatingPanelController: NSObject {
    enum Content { case snippets, authorization }
    private(set) var content: Content = .snippets
    let panel: FloatingPanel
    var onInsert: ((UUID) -> Void)?
    var onDismiss: (() -> Void)?
    var onAuthorizationAction: ((AuthorizationAction) -> Void)?
    var onApplicationDragEnded: ((Bool) -> Void)?
    private var authorizationFeedback = NSTextField(labelWithString: "")
    private var restartButton: NSButton?
    var isAuthorization: Bool { content == .authorization && isPresented }
    private var snippets: [Snippet] = []
    private var page = 0
    private var layout: PillLayout?
    private var status = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []
    private var hitPaths: [CGPath] = []
    private var closeFrame = CGRect.zero
    private var presentation = MenuPresentation()
    private var globalMotion: Any?
    private var localMotion: Any?
    private var globalActivity: Any?
    private var overlayWatch: Timer?
    private var followedSettingsFrame: CGRect?
    private var previousFlags: UInt = 0
    var isOwnShortcut: ((NSEvent) -> Bool)?
    var shortcutModifiers: (() -> NSEvent.ModifierFlags)?
    var isPresented: Bool { presentation.presented }

    override init() {
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("悬浮文案胶囊菜单")
    }
    // Also used by the offscreen native rendering check, without opening a window or requiring AX permissions.
    func configure(profile: AppProfile, at point: CGPoint, visible: CGRect) {
        content = .snippets; panel.isMovableByWindowBackground = false
        panel.title = "PhrasePerch — 快捷栏"
        panel.setAccessibilityLabel("悬浮文案胶囊菜单")
        snippets = profile.buttons.filter(\.isEnabled); page = 0
        layout = PillLayout(anchor: point, visible: visible, count: min(snippets.count, 5) + (snippets.count > 5 ? 1 : 0))
        render()
    }
    func configureAuthorization(applicationURL: URL, frame: CGRect) {
        content = .authorization; panel.isMovableByWindowBackground = true
        panel.title = "PhrasePerch — 授权引导"
        panel.setAccessibilityLabel("PhrasePerch 授权引导")
        panel.setFrame(frame, display: false)
        let root = AuthorizationBackdrop(frame: CGRect(origin: .zero, size: frame.size))
        root.material = .popover; root.state = .active; root.blendingMode = .behindWindow
        root.appearance = NSAppearance(named: .darkAqua)
        root.wantsLayer = true; root.layer?.cornerRadius = 14; root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0.8; root.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        let arrow = DragInstructionView(frame: CGRect(x: 12, y: 70, width: 26, height: 26))
        root.addSubview(arrow); arrow.animateHand()
        authorizationFeedback = NSTextField(wrappingLabelWithString: "")
        authorizationFeedback.frame = CGRect(x: 48, y: 59, width: frame.width - 80, height: 43)
        authorizationFeedback.font = .systemFont(ofSize: 12, weight: .medium)
        root.addSubview(authorizationFeedback)
        let icon = ApplicationDragView(applicationURL: applicationURL, frame: CGRect(x: 16, y: 15, width: 32, height: 32))
        let generation = presentation.generation
        icon.onDragEnded = { [weak self] accepted in
            guard let self, self.isAuthorization, self.presentation.generation == generation else { return }
            if accepted { self.hide() }
            self.onApplicationDragEnded?(accepted)
        }
        root.addSubview(icon)
        let name = NSTextField(labelWithString: "PhrasePerch")
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.frame = CGRect(x: 58, y: 21, width: 106, height: 22); root.addSubview(name)
        buttons = []; hitPaths = []
        func button(_ title: String, x: CGFloat, width: CGFloat, action: Selector) -> NSButton {
            let button = FloatingButton(frame: CGRect(x: x, y: 16, width: width, height: 28))
            button.title = title; button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 11)
            button.target = self; button.action = action
            root.addSubview(button); buttons.append(button); return button
        }
        restartButton = button("重启", x: frame.width - 60, width: 48, action: #selector(restartAuthorization))
        let close = FloatingButton(frame: CGRect(x: frame.width - 26, y: 82, width: 18, height: 20))
        close.title = "×"; close.isBordered = false; close.target = self; close.action = #selector(dismiss)
        close.setAccessibilityLabel("关闭授权引导"); root.addSubview(close); buttons.append(close)
        panel.contentView = root
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
    func showAuthorization(status: InputAuthorizationStatus, feedback: String, applicationURL: URL) {
        removeMotionObservers()
        let settings = settingsWindowFrame()
        let screen = NSScreen.screens.first { $0.frame.contains(settings.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let token = presentation.show()
        configureAuthorization(applicationURL: applicationURL,
                               frame: authorizationGuideFrame(settings: settings, visible: screen.visibleFrame))
        updateAuthorization(status: status, feedback: feedback)
        buttons.forEach { $0.isEnabled = false }
        panel.alphaValue = 0; panel.ignoresMouseEvents = true; panel.orderFrontRegardless()
        followedSettingsFrame = settings
        overlayWatch = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isAuthorization, self.presentation.generation == token,
                      let current = self.settingsWindowFrame() else { return }
                let previous = self.followedSettingsFrame
                self.followedSettingsFrame = current
                guard let previous else { return }
                guard current.origin != previous.origin,
                      let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: current.midX, y: current.midY)) }) ?? NSScreen.main else { return }
                let offset = CGPoint(x: current.minX - previous.minX, y: current.minY - previous.minY)
                let frame = self.panel.frame.offsetBy(dx: offset.x, dy: offset.y)
                self.panel.setFrameOrigin(CGPoint(x: max(screen.visibleFrame.minX, min(frame.minX, screen.visibleFrame.maxX - frame.width)),
                                                 y: max(screen.visibleFrame.minY, min(frame.minY, screen.visibleFrame.maxY - frame.height))))
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18; panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentation.finishShow(token) else { return }
                self.buttons.forEach { $0.isEnabled = true }; self.panel.ignoresMouseEvents = false
            }
        }
    }
    func updateAuthorization(status: InputAuthorizationStatus, feedback: String) {
        guard content == .authorization else { return }
        authorizationFeedback.stringValue = status == .needsPasteAccess
            ? "识别已授权；若已开启开关，请重启使粘贴生效。"
            : (status == .ready ? "授权完成，可以自动粘贴。" :
                (feedback.hasPrefix("未接受") ? "未接受拖入，请重试；也可用列表的“＋”选择应用。" :
                    "将图标拖入应用列表，然后开启 PhrasePerch 的开关。"))
        authorizationFeedback.toolTip = feedback
        restartButton?.isHidden = status != .needsPasteAccess
    }
    @objc private func restartAuthorization() { onAuthorizationAction?(.restart) }
    @discardableResult
    func show(profile: AppProfile, at point: CGPoint) -> Bool {
        removeMotionObservers()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return false }
        let total = profile.buttons.filter(\.isEnabled).count
        let nextLayout = PillLayout(anchor: point, visible: screen.visibleFrame, count: min(total, 5) + (total > 5 ? 1 : 0))
        guard !foreignOverlayVisible(frame: nextLayout.frame) else { return false }
        let token = presentation.show()
        configure(profile: profile, at: point, visible: screen.visibleFrame)
        buttons.forEach { $0.isEnabled = false }
        panel.ignoresMouseEvents = true; panel.alphaValue = 0
        panel.orderFrontRegardless(); installMotionObservers()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = panel.contentView?.layer, let layout {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.88; scale.toValue = 1.0; scale.duration = 0.18
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.anchorPoint = CGPoint(x: layout.center.x / layout.frame.width, y: layout.center.y / layout.frame.height)
            layer.position = layout.center
            layer.add(scale, forKey: "entrance")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentation.finishShow(token) else { return }
                self.buttons.forEach { $0.isEnabled = true }
                self.refreshMousePassThrough()
            }
        }
        return true
    }
    func hide() {
        let token = presentation.hide()
        panel.ignoresMouseEvents = true; buttons.forEach { $0.isEnabled = false }
        panel.contentView?.layer?.removeAllAnimations(); removeMotionObservers()
        for view in panel.contentView?.subviews ?? [] {
            view.layer?.removeAllAnimations(); view.layer?.sublayers?.forEach { $0.removeAllAnimations() }
        }
        guard panel.isVisible else { _ = presentation.finishHide(token); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10; panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentation.finishHide(token) else { return }
                self.panel.orderOut(nil)
            }
        }
    }
    func updateStatus(_ text: String, busy: Bool) {
        status.stringValue = text; status.toolTip = text
        buttons.forEach { $0.isEnabled = !busy && presentation.phase == .visible }
    }
    func isInteractive(_ point: CGPoint) -> Bool {
        closeFrame.contains(point) || hitPaths.contains { $0.contains(point) }
    }
    private func refreshMousePassThrough() {
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        panel.ignoresMouseEvents = presentation.phase != .visible || !isInteractive(local)
    }
    private func installMotionObservers() {
        removeMotionObservers()
        previousFlags = NSEvent.modifierFlags.rawValue
        globalActivity = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            self?.observeActivity(event)
        }
        // ponytail: window levels are a heuristic; a peer cooperation API is needed for a guaranteed handoff before its first frame.
        // Observe metadata only while open; never intercept another app's events.
        overlayWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPresented, self.foreignOverlayVisible(frame: self.panel.frame) else { return }
                self.dismissForForeignActivity()
            }
        }
        globalMotion = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.refreshMousePassThrough() }
        localMotion = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .keyDown, .flagsChanged, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            self?.refreshMousePassThrough()
            if [.keyDown, .flagsChanged, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(event.type) {
                self?.observeActivity(event)
            }
            return event
        }
    }
    private func observeActivity(_ event: NSEvent) {
        guard isPresented else { return }
        // Our single synthetic paste must not cancel its own readback.
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == clipboardPasteEventTag { return }
        if event.type == .flagsChanged {
            let newPress = pressedNewModifier(previous: previousFlags, current: event.modifierFlags.rawValue)
            previousFlags = event.modifierFlags.rawValue
            if !newPress { return }
            let held = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if let own = shortcutModifiers?(), !held.isEmpty, held.isSubset(of: own) { return }
        } else if event.type == .keyDown && isOwnShortcut?(event) == true { return }
        dismissForForeignActivity()
    }
    private func removeMotionObservers() {
        if let globalMotion { NSEvent.removeMonitor(globalMotion) }
        if let localMotion { NSEvent.removeMonitor(localMotion) }
        if let globalActivity { NSEvent.removeMonitor(globalActivity) }
        overlayWatch?.invalidate(); overlayWatch = nil; globalActivity = nil
        followedSettingsFrame = nil
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
        buttons = []; hitPaths = []
        let indices = snippetPage(count: snippets.count, page: page)
        let hasPages = snippets.count > 5
        let count = indices.count + (hasPages ? 1 : 0)
        let effect = NSVisualEffectView(frame: layout.bar)
        effect.material = .popover; effect.state = .active; effect.blendingMode = .behindWindow
        effect.wantsLayer = true; effect.layer?.cornerRadius = 24; effect.layer?.masksToBounds = true
        root.addSubview(effect)
        let backdrop = PillBackdrop(frame: root.bounds); backdrop.shape = layout.shape; root.addSubview(backdrop)
        for slot in 0..<count {
            let rect = layout.itemRect(index: slot)
            let shape = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            let button = PillButton(frame: rect)
            var transform = CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
            button.shape = shape.copy(using: &transform) ?? shape
            let label = CGPoint(x: rect.midX, y: rect.midY)
            button.labelCenter = CGPoint(x: label.x - rect.minX, y: label.y - rect.minY)
            button.isBordered = false; button.target = self; button.focusRingType = .none
            if slot < indices.count {
                let index = indices.lowerBound + slot, title = snippets[index].title
                button.title = String(title.prefix(4)) + (title.count > 4 ? "…" : "")
                button.setAccessibilityLabel(title); button.tag = index; button.action = #selector(insert(_:))
                button.toolTip = String(snippets[index].text.prefix(180))
            } else {
                button.title = indices.upperBound == snippets.count ? "首页" : "•••"
                button.setAccessibilityLabel(indices.upperBound == snippets.count ? "首页" : "更多文案"); button.action = #selector(nextPage)
            }
            hitPaths.append(shape); buttons.append(button); root.addSubview(button)
            let separator = NSBox(frame: CGRect(x: rect.maxX, y: layout.bar.midY - 8, width: 1, height: 16))
            separator.boxType = .custom; separator.borderWidth = 0
            separator.fillColor = NSColor.white.withAlphaComponent(0.15); root.addSubview(separator)
        }
        closeFrame = layout.closeFrame
        let close = FloatingButton(frame: closeFrame)
        close.title = "×"; close.isBordered = false; close.font = .systemFont(ofSize: 17)
        close.target = self; close.action = #selector(dismiss); close.setAccessibilityLabel("关闭快捷栏")
        root.addSubview(close)
        status = NSTextField(labelWithString: "")
        status.frame = CGRect(x: 6, y: 1, width: layout.bar.width, height: 18)
        status.font = .systemFont(ofSize: 10); status.textColor = .secondaryLabelColor
        status.alignment = .center; status.maximumNumberOfLines = 1; status.lineBreakMode = .byTruncatingTail
        root.addSubview(status); panel.contentView = root
    }
    @objc private func insert(_ sender: NSButton) {
        guard presentation.phase == .visible, snippets.indices.contains(sender.tag) else { return }
        onInsert?(snippets[sender.tag].id)
    }
    @objc private func nextPage() {
        guard presentation.phase == .visible else { return }
        page = (page + 1) % max(1, (snippets.count + 4) / 5)
        render(); refreshMousePassThrough()
    }
    @objc private func dismiss() { if presentation.phase == .visible { onDismiss?() } }
}
