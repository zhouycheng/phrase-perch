import AppKit
import KeyboardShortcuts
import SwiftUI

struct EditorRingLayout {
    static let buttonSize = CGSize(width: 88, height: 36)
    static let cornerRadius: CGFloat = 12
    let items: [CGRect]

    // Distance between the actual rounded edges, rather than between centers.
    static func edgeGap(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let dx = max(0, abs(first.midX - second.midX) - (first.width - 2 * cornerRadius))
        let dy = max(0, abs(first.midY - second.midY) - (first.height - 2 * cornerRadius))
        return hypot(dx, dy) - 2 * cornerRadius
    }

    init(size: CGSize, count: Int) {
        guard count > 0, count <= SnippetEditorSession.pageSize else {
            items = []
            return
        }
        let radius = max(
            0,
            min(
                140, (size.width - Self.buttonSize.width - 48) / 2,
                (size.height - Self.buttonSize.height - 48) / 2))
        func rect(at angle: CGFloat) -> CGRect {
            CGRect(
                x: size.width / 2 + sin(angle) * radius - Self.buttonSize.width / 2,
                y: size.height / 2 - cos(angle) * radius - Self.buttonSize.height / 2,
                width: Self.buttonSize.width, height: Self.buttonSize.height)
        }
        func nextAngle(after angle: CGFloat, gap: CGFloat) -> CGFloat {
            let first = rect(at: angle)
            var low: CGFloat = 0
            var high = CGFloat.pi
            guard Self.edgeGap(first, rect(at: angle + high)) >= gap else { return .infinity }
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if Self.edgeGap(first, rect(at: angle + middle)) < gap { low = middle } else { high = middle }
            }
            return angle + (low + high) / 2
        }
        guard count > 2 else {
            items = (0..<count).map { rect(at: CGFloat($0) * 2 * .pi / CGFloat(count)) }
            return
        }
        // Solve the common clearance that closes one complete circle.
        var low: CGFloat = 0
        var high = radius * 2
        for _ in 0..<28 {
            let gap = (low + high) / 2
            var angle: CGFloat = 0
            for _ in 0..<count {
                angle = nextAngle(after: angle, gap: gap)
                if !angle.isFinite { break }
            }
            if angle > 2 * .pi { high = gap } else { low = gap }
        }
        let gap = (low + high) / 2
        var angle: CGFloat = 0
        var placed = [rect(at: angle)]
        for _ in 1..<count {
            angle = nextAngle(after: angle, gap: gap)
            placed.append(rect(at: angle))
        }
        items = placed
    }
}
