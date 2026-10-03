import Foundation
import Observation

@MainActor @Observable
final class FloatingMenuViewModel {
    private(set) var snippets: [Snippet] = []
    private(set) var layout: RadialLayout?
    private(set) var selectedID: UUID?
    private(set) var failureMessage = ""
    private var movement = SelectionMovement(initialMouse: .zero, requiresMovement: false)
    private var presentation = MenuPresentation()
    var isPresented: Bool { presentation.presented }
    func configure(profile: AppProfile, at point: CGPoint, visible: CGRect) -> Bool {
        let enabled = profile.buttons.filter(\.isEnabled)
        guard let next = RadialLayout(anchor: point, visible: visible, count: enabled.count) else {
            failureMessage = "文案无法完整排入当前屏幕，请减少启用文案数量。"
            return false
        }
        snippets = enabled
        layout = next
        selectedID = nil
        failureMessage = ""
        return true
    }
    func fail(_ message: String) { failureMessage = message }
    func beginShow(initialMouse: CGPoint, requiresMovement: Bool) -> Int {
        movement = SelectionMovement(initialMouse: initialMouse, requiresMovement: requiresMovement)
        return presentation.show()
    }
    func beginHide() -> Int {
        selectedID = nil
        return presentation.hide()
    }
    func finishShow(_ token: Int) -> Bool { presentation.finishShow(token) }
    func finishHide(_ token: Int) -> Bool { presentation.finishHide(token) }
    func select(at screenPoint: CGPoint, hitID: UUID?) -> UUID? {
        guard isPresented else {
            selectedID = nil
            return nil
        }
        selectedID = movement.update(screenPoint) && snippets.contains(where: { $0.id == hitID }) ? hitID : nil
        return selectedID
    }
}
