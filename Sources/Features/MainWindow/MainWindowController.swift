import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    private var settingsWindow: NSWindow?
    private let viewModel: MainWindowViewModel
    private let preferences: PreferencesViewModel
    init(viewModel: MainWindowViewModel, preferences: PreferencesViewModel) {
        self.viewModel = viewModel
        self.preferences = preferences
    }
    func open() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 960, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "PhrasePerch"
            window.titleVisibility = .visible
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: MainWindowView(viewModel: viewModel, preferences: preferences))
            window.setContentSize(CGSize(width: 960, height: 620))
            window.contentMinSize = CGSize(width: 880, height: 560)
            window.backgroundColor = NSColor(calibratedWhite: 23 / 255, alpha: 1)
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
