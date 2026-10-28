import AppKit
import SwiftUI

@MainActor
final class PermissionSetupWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let viewModel: PermissionSetupViewModel
    private var refreshTimer: Timer?

    init(viewModel: PermissionSetupViewModel) {
        self.viewModel = viewModel
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "PhrasePerch — 系统权限"
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.13, alpha: 1)
        window.contentMinSize = CGSize(width: 460, height: 430)
        window.delegate = self
        let content = NSHostingView(rootView: PermissionSetupContent(viewModel: viewModel,
            onClose: { [weak self] in self?.window.close() }))
        // The window owns its size; the flexible SwiftUI root fills those bounds.
        content.sizingOptions = []
        window.contentView = content
        window.setContentSize(CGSize(width: 460, height: 430))
        window.center()
    }
    func show() {
        viewModel.refresh()
        window.makeKeyAndOrderFront(nil)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.viewModel.refresh() }
        }
    }
    func windowDidBecomeKey(_ notification: Notification) { viewModel.refresh() }
    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

private struct PermissionSetupContent: View {
    let viewModel: PermissionSetupViewModel
    let onClose: () -> Void
    var body: some View {
        PermissionSetupView(requirements: viewModel.requirements, isRestarting: viewModel.isRestarting,
            feedback: viewModel.feedback, onAction: viewModel.performAction, onClose: onClose)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewModel.refresh()
            }
    }
}
