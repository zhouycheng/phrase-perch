import ApplicationServices
import Foundation

// The callback registry keeps notification delivery independent of observer teardown.
private final class AXObservationRegistry: @unchecked Sendable {
    static let shared = AXObservationRegistry()
    private let lock = NSLock()
    private var callbacks: [UInt: @Sendable () -> Void] = [:]
    func set(_ observer: AXObserver, callback: (@Sendable () -> Void)?) {
        lock.lock()
        callbacks[UInt(bitPattern: Unmanaged.passUnretained(observer).toOpaque())] = callback
        lock.unlock()
    }
    func deliver(_ observer: AXObserver) {
        lock.lock()
        let callback = callbacks[UInt(bitPattern: Unmanaged.passUnretained(observer).toOpaque())]
        lock.unlock()
        callback?()
    }
}

final class AXFocusObservation: @unchecked Sendable {
    private let observer: AXObserver
    private let lock = NSLock()
    private var dirty = false
    private(set) var tracksSelection = false
    var changed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return dirty
    }
    private func markChanged() {
        lock.lock()
        dirty = true
        lock.unlock()
    }
    init?(pid: pid_t, app: AXUIElement, editor: AXUIElement, window: AXUIElement?, onChange: @escaping @Sendable () -> Void) {
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { observer, _, _, _ in
            AXObservationRegistry.shared.deliver(observer)
        }, &observer)
        guard result == .success, let observer else { return nil }
        self.observer = observer
        AXObservationRegistry.shared.set(observer) { [weak self] in
            self?.markChanged()
            onChange()
        }
        var notifications = [
            (app, kAXFocusedUIElementChangedNotification), (app, kAXFocusedWindowChangedNotification),
            (editor, kAXSelectedTextChangedNotification), (editor, kAXUIElementDestroyedNotification),
        ]
        if let window { notifications += [(window, kAXMovedNotification), (window, kAXResizedNotification)] }
        for (element, notification) in notifications {
            if Task.isCancelled { break }
            AXUIElementSetMessagingTimeout(element, 0.1)
            let result = AXObserverAddNotification(observer, element, notification as CFString, nil)
            if notification == kAXSelectedTextChangedNotification, result == .success { tracksSelection = true }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    deinit {
        AXObservationRegistry.shared.set(observer, callback: nil)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}
