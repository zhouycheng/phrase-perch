import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var settingsWindow: NSWindow?
    private let viewModel: MainWindowViewModel
    private let preferences: PreferencesViewModel
    var onClose: (() -> Void)?
    init(viewModel: MainWindowViewModel, preferences: PreferencesViewModel) {
        self.viewModel = viewModel
        self.preferences = preferences
        super.init()
    }
    func open() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: EditorColumns.windowSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "PhrasePerch"
            window.titleVisibility = .visible
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(
                rootView: MainWindowView(viewModel: viewModel, preferences: preferences))
            window.setContentSize(EditorColumns.windowSize)
            window.contentMinSize = EditorColumns.windowSize
            window.backgroundColor = NSColor(calibratedWhite: 23 / 255, alpha: 1)
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        NSApp.unhide(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = sender.frameRect(forContentRect: CGRect(origin: .zero, size: EditorColumns.windowSize)).size
        return CGSize(width: max(minimum.width, frameSize.width), height: max(minimum.height, frameSize.height))
    }
}
