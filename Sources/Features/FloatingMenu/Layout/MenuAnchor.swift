import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

struct MenuAnchor: Equatable {
    let point: CGPoint
    let usedMouseFallback: Bool
    let usedEditorFallback: Bool
    var source: String { usedMouseFallback ? "鼠标回退" : usedEditorFallback ? "输入框边界" : "首选位置" }
    var detail: String {
        usedMouseFallback ? "光标位置不可用，已在鼠标附近展开。" : usedEditorFallback ? "光标位置不可用，已在输入框可见区域展开。" : ""
    }
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
                point = CGPoint(x: max(visible.minX, min(mouse.x, visible.maxX - 1)),
                    y: max(visible.minY, min(mouse.y, visible.maxY - 1)))
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
