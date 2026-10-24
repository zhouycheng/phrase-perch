import Foundation
import Observation

@MainActor @Observable
final class FloatingMenuViewModel {
    private(set) var page: RadialPage?
    var layout: RadialLayout? { page?.layout }
    private(set) var selectedID: UUID?
    private(set) var failureMessage = ""
    private(set) var acceptsHover = false
    private var movement = SelectionMovement(initialMouse: .zero, requiresMovement: false)
    private var presentation = MenuPresentation()
    var isPresented: Bool { presentation.presented }
    func configure(profile: AppProfile, at point: CGPoint, visible: CGRect) -> Bool {
        configure(nodes: RadialNode.contents(profile: profile, group: nil), at: point, visible: visible)
    }
    func configure(nodes: [RadialNode], at point: CGPoint, visible: CGRect, hasPrevious: Bool = false,
        previousAngle: CGFloat? = nil) -> Bool {
        guard let page = RadialPage(nodes: nodes, anchor: point, visible: visible,
            hasPrevious: hasPrevious, previousAngle: previousAngle) else {
            failureMessage = "当前屏幕空间不足，无法展示轮盘。"
            return false
        }
        restore(page)
        failureMessage = ""
        return true
    }
    func restore(_ page: RadialPage) {
        self.page = page
        selectedID = nil
    }
    func resetSelection(at point: CGPoint) {
        selectedID = nil
        acceptsHover = false
        movement = SelectionMovement(initialMouse: point, requiresMovement: true)
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
        acceptsHover = movement.update(screenPoint)
        selectedID = acceptsHover && page?.slots.contains(where: { $0?.textID != nil && $0?.textID == hitID }) == true ? hitID : nil
        return selectedID
    }
}
