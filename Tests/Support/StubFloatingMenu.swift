import AppKit
@testable import PhrasePerch

@MainActor
final class StubFloatingMenu: FloatingMenuPresenting {
    var onDismiss: (() -> Void)?
    var onSelect: ((UUID) -> Void)?
    var interactionMode = MenuInteractionMode.hold
    var titleCharacterLimit = 10
    var menuAppearance = MenuAppearance.matte
    var isPresented = false
    var frame = CGRect(x: 0, y: 0, width: 300, height: 300)
    var failureMessage = ""
    var selected: UUID?
    var shows = 0
    var messages: [String] = []
    func show(profile: AppProfile, at point: CGPoint, initialMouse: CGPoint?, requiresMovement: Bool) -> Bool {
        isPresented = true
        shows += 1
        return true
    }
    func showStatus(_ message: String, at point: CGPoint) { messages.append(message) }
    func hide() { isPresented = false }
    func isInteractive(_ point: CGPoint) -> Bool { frame.contains(point) }
    func updateSelection(at screenPoint: CGPoint) -> UUID? { selected }
}
