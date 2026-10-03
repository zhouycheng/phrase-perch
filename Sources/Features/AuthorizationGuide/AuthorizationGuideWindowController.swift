import AppKit
import QuartzCore

@MainActor
final class AuthorizationGuideWindowController: NSObject, AuthorizationGuidePresenting {
    let panel = AuthorizationGuidePanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let viewModel = AuthorizationGuideViewModel()
    var onDragEnded: ((Bool) -> Void)?
    private var followTimer: Timer?
    private var previousSettingsFrame: CGRect?
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
        configure(
            applicationURL: applicationURL,
            frame: authorizationGuideFrame(settings: settings, visible: screen.visibleFrame))
        previousSettingsFrame = settings
        viewModel.show(applicationURL: applicationURL)
        panel.orderFrontRegardless()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible, let frame = self.settingsWindowFrame() else { return }
                defer { self.previousSettingsFrame = frame }
                guard let previous = self.previousSettingsFrame, frame.origin != previous.origin,
                    let screen = NSScreen.screens.first(where: {
                        $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
                    })
                else { return }
                let translated = self.panel.frame.offsetBy(
                    dx: frame.minX - previous.minX, dy: frame.minY - previous.minY)
                self.panel.setFrameOrigin(
                    CGPoint(
                        x: max(
                            screen.visibleFrame.minX, min(translated.minX, screen.visibleFrame.maxX - translated.width)),
                        y: max(
                            screen.visibleFrame.minY, min(translated.minY, screen.visibleFrame.maxY - translated.height)
                        )))
            }
        }
    }
    @objc func hide() {
        followTimer?.invalidate()
        followTimer = nil
        viewModel.hide()
        panel.orderOut(nil)
    }
    private func settingsWindowFrame() -> CGRect? {
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
                .first?.processIdentifier,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let entry = windows.first(where: {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
            }),
            let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
}
