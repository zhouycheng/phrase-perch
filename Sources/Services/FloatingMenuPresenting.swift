import AppKit

@MainActor
protocol FloatingMenuPresenting: AnyObject {
    var isPresented: Bool { get }
    var frame: CGRect { get }
    var failureMessage: String { get }
    var onDismiss: (() -> Void)? { get set }
    func show(profile: AppProfile, at point: CGPoint, initialMouse: CGPoint?, requiresMovement: Bool) -> Bool
    func hide()
    func isInteractive(_ point: CGPoint) -> Bool
    func updateSelection(at screenPoint: CGPoint) -> UUID?
}
