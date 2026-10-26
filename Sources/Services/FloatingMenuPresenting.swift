import AppKit

@MainActor
protocol FloatingMenuPresenting: AnyObject {
    var isPresented: Bool { get }
    var frame: CGRect { get }
    var failureMessage: String { get }
    var onDismiss: (() -> Void)? { get set }
    var onSelect: ((UUID) -> Void)? { get set }
    var interactionMode: MenuInteractionMode { get set }
    var titleCharacterLimit: Int { get set }
    func showStatus(_ message: String, at point: CGPoint)
    func show(profile: AppProfile, at point: CGPoint, initialMouse: CGPoint?, requiresMovement: Bool) -> Bool
    func hide()
    func isInteractive(_ point: CGPoint) -> Bool
    func updateSelection(at screenPoint: CGPoint) -> UUID?
}
