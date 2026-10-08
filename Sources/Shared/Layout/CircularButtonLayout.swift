import CoreGraphics

enum CircularButtonLayout {
    static let cornerRadius: CGFloat = 12

    static func edgeGap(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let dx = max(0, abs(first.midX - second.midX) - (first.width + second.width) / 2 + 2 * cornerRadius)
        let dy = max(0, abs(first.midY - second.midY) - (first.height + second.height) / 2 + 2 * cornerRadius)
        return hypot(dx, dy) - 2 * cornerRadius
    }

    static func items(count: Int, radius: CGFloat, buttonSize: CGSize) -> [CGRect] {
        guard count > 0 else { return [] }
        func rect(at angle: CGFloat) -> CGRect {
            CGRect(x: sin(angle) * radius - buttonSize.width / 2,
                y: -cos(angle) * radius - buttonSize.height / 2,
                width: buttonSize.width, height: buttonSize.height)
        }
        if count <= 2 {
            return (0..<count).map { rect(at: CGFloat($0) * 2 * .pi / CGFloat(count)) }
        }
        if count <= 8, radius < buttonSize.width {
            // Keep wide horizontal capsules on the circle with clearance above and below the side items.
            if count <= 4 {
                return (0..<count).map { rect(at: CGFloat($0) * 2 * .pi / CGFloat(count)) }
            }
            if count <= 6 {
                let angles: [CGFloat] = [0, .pi / 3, 2 * .pi / 3, .pi, 4 * .pi / 3, 5 * .pi / 3]
                return angles.prefix(count).map { rect(at: $0) }
            }
            var angles: [CGFloat] = [0, .pi / 3, .pi / 2, 2 * .pi / 3, .pi, 4 * .pi / 3, 3 * .pi / 2, 5 * .pi / 3]
            if count == 7 { angles.remove(at: 2) }
            return angles.map { rect(at: $0) }
        }
        func nextAngle(after angle: CGFloat, gap: CGFloat) -> CGFloat {
            guard angle.isFinite else { return .infinity }
            let first = rect(at: angle)
            var low: CGFloat = 0
            var high = CGFloat.pi
            guard edgeGap(first, rect(at: angle + high)) >= gap else { return .infinity }
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if edgeGap(first, rect(at: angle + middle)) < gap { low = middle } else { high = middle }
            }
            return angle + (low + high) / 2
        }
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
            guard angle.isFinite else { return [] }
            placed.append(rect(at: angle))
        }
        return placed
    }
}
