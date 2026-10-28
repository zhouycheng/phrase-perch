import AppKit
import QuartzCore

@MainActor
final class AuthorizationGuideWindowController: NSObject, AuthorizationGuidePresenting {
    let panel = AuthorizationGuidePanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let viewModel = AuthorizationGuideViewModel()
    var onDragEnded: ((Bool) -> Void)?
    private var followTimer: Timer?
    private var settingsWindowID: CGWindowID?
    private(set) var manuallyPositioned = false
    func beginManualPlacement() { manuallyPositioned = true }
    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        panel.title = "PhrasePerch — 授权拖拽"
        panel.setAccessibilityLabel("PhrasePerch 授权拖拽")
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    func configure(applicationURL: URL, frame: CGRect) {
        panel.setFrame(frame, display: false)
        let root = AuthorizationGuideView(applicationURL: applicationURL, frame: frame)
        root.onBeginMoving = { [weak self] in self?.beginManualPlacement() }
        root.onClose = { [weak self] in self?.hide() }
        root.onDragEnded = { [weak self] accepted in
            guard let self else { return }
            viewModel.didDrag(accepted: accepted)
            if accepted { hide() }
            onDragEnded?(accepted)
        }
        panel.contentView = root
    }
    func show(applicationURL: URL) {
        hide()
        let settings = settingsWindowFrame()
        let point = settings.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        updatePlacement(applicationURL: applicationURL, settings: settings, visible: screen.visibleFrame)
        viewModel.show(applicationURL: applicationURL)
        panel.orderFrontRegardless()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                let settings = self.settingsWindowFrame()
                let frame = self.manuallyPositioned ? self.panel.frame : (settings ?? self.panel.frame)
                guard let screen = NSScreen.screens.first(where: {
                    $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
                }) ?? NSScreen.main else { return }
                self.updatePlacement(applicationURL: applicationURL, settings: settings, visible: screen.visibleFrame)
            }
        }
    }
    func updatePlacement(applicationURL: URL, settings: CGRect?, visible: CGRect) {
        let destination = manuallyPositioned
            ? clampedAuthorizationGuideFrame(panel.frame, visible: visible)
            : authorizationGuideFrame(settings: settings, visible: visible)
        if panel.contentView == nil || destination.size != panel.frame.size {
            configure(applicationURL: applicationURL, frame: destination)
        } else if panel.frame != destination {
            panel.setFrame(destination, display: true)
        }
    }
    @objc func hide() {
        followTimer?.invalidate()
        followTimer = nil
        settingsWindowID = nil
        manuallyPositioned = false
        viewModel.hide()
        panel.orderOut(nil)
    }
    private func settingsWindowFrame() -> CGRect? {
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
                .first?.processIdentifier,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let entry = Self.settingsWindow(in: windows, pid: pid, trackedID: settingsWindowID),
            let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        settingsWindowID = entry[kCGWindowNumber as String] as? CGWindowID
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
    static func settingsWindow(in windows: [[String: Any]], pid: pid_t, trackedID: CGWindowID?) -> [String: Any]? {
        let candidates = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                && ($0[kCGWindowLayer as String] as? Int) == 0
        }
        if let trackedID {
            return candidates.first { ($0[kCGWindowNumber as String] as? CGWindowID) == trackedID }
        }
        return candidates.filter { area(of: $0) > 0 }.max { area(of: $0) < area(of: $1) }
    }
    private static func area(of window: [String: Any]) -> CGFloat {
        guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return 0 }
        return frame.width * frame.height
    }

}
