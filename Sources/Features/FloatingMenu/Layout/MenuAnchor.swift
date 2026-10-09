import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

struct MenuAnchor: Equatable {
    let point: CGPoint
    let usedMouseFallback: Bool
    let usedEditorFallback: Bool
    init(
        mode: MenuAnchorMode, mouse: CGPoint, caretBounds: CGRect?, primaryScreenTop: CGFloat,
        screens: [CGRect], editorBounds: CGRect? = nil
    ) {
        let editor = editorBounds.flatMap { rect -> CGRect? in
            guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
                rect.width > 0, rect.height > 0
            else { return nil }
            return rect
        }
        if mode == .caret, let rect = caretBounds,
            rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
            rect.width >= 0, rect.height > 0,
            editor.map({ $0.insetBy(dx: -2, dy: -2).contains(CGPoint(x: rect.midX, y: rect.midY))
                && rect.height <= $0.height + 4 }) ?? true
        {
            let candidate = flippedScreenPoint(CGPoint(x: rect.midX, y: rect.midY), primaryScreenTop: primaryScreenTop)
            if screens.contains(where: { $0.contains(candidate) }) {
                point = candidate
                usedMouseFallback = false
                usedEditorFallback = false
                return
            }
        }
        // Scrolled text can report a caret outside its input, even on another visible part of the screen.
        if mode == .caret, let editor {
            let converted = CGRect(
                x: editor.minX, y: primaryScreenTop - editor.maxY, width: editor.width, height: editor.height)
            let visible = screens.map { $0.intersection(converted) }.filter { !$0.isNull && !$0.isEmpty }
                .max { $0.width * $0.height < $1.width * $1.height }
            if let visible {
                point = CGPoint(x: visible.midX, y: visible.midY)
                usedMouseFallback = false
                usedEditorFallback = true
                return
            }
        }
        point = mouse
        usedMouseFallback = mode == .caret
        usedEditorFallback = false
    }
}
