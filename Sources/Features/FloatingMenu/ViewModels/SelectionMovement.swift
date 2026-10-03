import AppKit
import QuartzCore

struct SelectionMovement {
    let initialMouse: CGPoint
    let requiresMovement: Bool
    private(set) var armed = false
    mutating func update(_ point: CGPoint) -> Bool {
        if !requiresMovement || hypot(point.x - initialMouse.x, point.y - initialMouse.y) > 3 { armed = true }
        return armed
    }
}
