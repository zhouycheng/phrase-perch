import AppKit
@testable import PhrasePerch

@MainActor
final class StubTriggerSource: TriggerEventSource {
    var onFrontChanged: (() -> Void)?
    var onSessionChanged: ((Bool) -> Void)?
    var onInvalidated: (() -> Void)?
    var onPermissionsChanged: (() -> Void)?
    var onEvent: ((NSEvent) -> Void)?
    var onShortcutDown: (() -> Void)?
    var onShortcutUp: (() -> Void)?
    var enabled = false
    func start() {}
    func stop() {}
    func setShortcutEnabled(_ enabled: Bool) { self.enabled = enabled }
}
