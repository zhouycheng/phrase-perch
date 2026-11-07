import AppKit
import SwiftUI

struct ContentListInteraction: NSViewRepresentable {
    static let holdDuration: Duration = .milliseconds(600)
    var prepare: () -> Void
    var rowAt: (CGPoint) -> UUID?
    var isBlank: (CGPoint) -> Bool
    var lift: (UUID, CGPoint) -> Void
    var beginMarquee: (CGPoint, Bool) -> Void
    var move: (CGPoint, Bool) -> Void
    var finish: (CGPoint) -> Void
    var cancel: () -> Void
    var clickBlank: () -> Void
    var isActive: () -> Bool
    var screenChanged: (CGRect?) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.interaction = self
        return view
    }
    func updateNSView(_ view: ObserverView, context: Context) { view.interaction = self }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stop() }

    final class ObserverView: NSView {
        var interaction: ContentListInteraction?
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var holdTask: Task<Void, Never>?
        private var start: CGPoint?
        private var pointer = CGPoint.zero
        private var candidate: UUID?
        private var blank = false
        private var additive = false
        private var tracking = false
        private var lifted = false
        private var ignored = false
        private var lastScreen: CGRect?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]) {
                [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handle(event) == nil }
                return consumed ? nil : event
            }
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelPress() }
                })
            }
            for (name, object) in [(NSWindow.didChangeScreenNotification, window as AnyObject?),
                (NSApplication.didChangeScreenParametersNotification, nil)] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportScreen() }
                })
            }
            reportScreen()
        }

        func stop() {
            holdTask?.cancel(); holdTask = nil
            if tracking || candidate != nil { interaction?.cancel() }
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            resetPress()
            lastScreen = nil
        }

        private func reportScreen() {
            let visible = window?.screen?.visibleFrame
            guard visible != lastScreen else { return }
            lastScreen = visible
            cancelPress()
            DispatchQueue.main.async { [weak self] in self?.interaction?.screenChanged(visible) }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, let interaction else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, start != nil {
                    cancelPress()
                    return nil
                }
                return event
            }
            let point = convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDown:
                resetPress()
                guard bounds.contains(point) else { return event }
                interaction.prepare()
                window?.contentView?.layoutSubtreeIfNeeded()
                pointer = point; start = point
                additive = event.modifierFlags.contains(.command)
                if let editor = window?.firstResponder as? NSTextView,
                    editor.convert(editor.bounds, to: self).contains(point) {
                    start = nil
                    return event
                }
                candidate = interaction.rowAt(point)
                blank = candidate == nil && interaction.isBlank(point)
                guard let candidate else { return event }
                holdTask = Task { [weak self] in
                    do { try await Task.sleep(for: ContentListInteraction.holdDuration) } catch { return }
                    guard let self, self.candidate == candidate, !ignored, window?.isKeyWindow == true,
                        self.interaction?.rowAt(pointer) == candidate else { return }
                    window?.makeFirstResponder(nil)
                    tracking = true; lifted = true
                    self.interaction?.lift(candidate, start ?? pointer)
                    self.interaction?.move(pointer, false)
                }
            case .leftMouseDragged:
                guard let start, !ignored else { return event }
                pointer = point
                let distance = hypot(point.x - start.x, point.y - start.y)
                if !tracking {
                    if candidate != nil && distance > 6 {
                        holdTask?.cancel(); candidate = nil
                    }
                    if blank && distance >= 3 {
                        tracking = true
                        interaction.beginMarquee(start, additive)
                    }
                }
                if tracking {
                    guard interaction.isActive() else { cancelPress(); return event }
                    interaction.move(point, !lifted || distance >= 3)
                }
            case .leftMouseUp:
                holdTask?.cancel()
                if !ignored {
                    if tracking && interaction.isActive() { interaction.finish(point) }
                    else if blank, let start, hypot(point.x - start.x, point.y - start.y) < 3 { interaction.clickBlank() }
                }
                resetPress()
            default: break
            }
            return event
        }

        private func cancelPress() {
            holdTask?.cancel(); holdTask = nil
            if start != nil { interaction?.cancel(); ignored = true }
            tracking = false; candidate = nil
        }
        private func resetPress() {
            holdTask?.cancel(); holdTask = nil
            start = nil; candidate = nil; blank = false; tracking = false; lifted = false; ignored = false
        }
    }
}
