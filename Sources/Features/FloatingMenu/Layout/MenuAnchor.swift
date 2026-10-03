import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

struct MenuAnchor: Equatable {
    let point: CGPoint
    let usedMouseFallback: Bool
    init(mode: MenuAnchorMode, mouse: CGPoint, caretBounds: CGRect?, primaryScreenTop: CGFloat, screens: [CGRect]) {
        if mode == .caret, let rect = caretBounds,
            rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
            rect.width >= 0, rect.height > 0
        {
            let candidate = flippedScreenPoint(CGPoint(x: rect.midX, y: rect.midY), primaryScreenTop: primaryScreenTop)
            if screens.contains(where: { $0.contains(candidate) }) {
                point = candidate
                usedMouseFallback = false
                return
            }
        }
        point = mouse
        usedMouseFallback = mode == .caret
    }
}
