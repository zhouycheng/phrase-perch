import AppKit

@MainActor
protocol TriggerEventSource: AnyObject {
    var onFrontChanged: (() -> Void)? { get set }
    var onSessionChanged: ((Bool) -> Void)? { get set }
    var onInvalidated: (() -> Void)? { get set }
    var onPermissionsChanged: (() -> Void)? { get set }
    var onEvent: ((NSEvent) -> Void)? { get set }
    var onShortcutDown: (() -> Void)? { get set }
    var onShortcutUp: (() -> Void)? { get set }
    func start()
    func stop()
    func setShortcutEnabled(_ enabled: Bool)
}
