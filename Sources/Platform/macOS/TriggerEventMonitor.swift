import AppKit
import KeyboardShortcuts
import Observation

@MainActor @Observable
final class TriggerEventMonitor {
    private(set) var mouseMonitorAvailable = false
    var onFrontChanged: (() -> Void)?
    var onSessionChanged: ((Bool) -> Void)?
    var onInvalidated: (() -> Void)?
    var onPermissionsChanged: (() -> Void)?
    var onEvent: ((NSEvent) -> Void)?
    var onShortcutDown: (() -> Void)?
    var onShortcutUp: (() -> Void)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var mouseMonitor: Any?
    private var localMonitor: Any?
    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.onFrontChanged?() }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] in self?.onFrontChanged?() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.onSessionChanged?(false)
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.onSessionChanged?(true)
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.onInvalidated?() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.onInvalidated?() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.onInvalidated?()
        }
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { [weak self] in
            self?.onPermissionsChanged?()
        }
        let events: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown,
            .flagsChanged, .keyDown, .keyUp, .scrollWheel,
        ]

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.onEvent?(event)
        }
        mouseMonitorAvailable = mouseMonitor != nil
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            if event.type == .keyDown,
                NSApp.isActive, NSApp.modalWindow == nil,
                isCommandQuitShortcut(
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                    modifiers: event.modifierFlags)
            {
                NSApp.terminate(nil)
                return nil
            }
            self?.onEvent?(event)
            return event
        }
        KeyboardShortcuts.onKeyDown(for: .toggleFloatingInputBar) { [weak self] in self?.onShortcutDown?() }
        KeyboardShortcuts.onKeyUp(for: .toggleFloatingInputBar) { [weak self] in self?.onShortcutUp?() }
    }
    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        callback: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { callback() }
        }
        observers.append((center, token))
    }
    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        mouseMonitor = nil
        localMonitor = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        KeyboardShortcuts.removeHandler(for: .toggleFloatingInputBar)
        KeyboardShortcuts.disable(.toggleFloatingInputBar)
    }
}
