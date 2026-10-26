import CoreGraphics

enum CircularButtonLayout {
    static let cornerRadius: CGFloat = 12

    static func outwardItems(widths: [CGFloat], height: CGFloat, pinnedIndex: Int = 0,
        angle: CGFloat? = nil) -> (items: [CGRect], radius: CGFloat) {
        guard widths.allSatisfy({ $0.isFinite && $0 >= 88 }) else { return ([], 0) }
        let base = items(count: widths.count, buttonSize: CGSize(width: 88, height: height), pinnedIndex: pinnedIndex, angle: angle)
        guard let first = base.first else { return ([], 0) }
        let initial = hypot(first.midX, first.midY)
        func template(_ radius: CGFloat) -> [CGRect] {
            zip(base, widths).map { rect, width in
                let x = rect.midX * radius / initial, y = rect.midY * radius / initial
                let left = abs(rect.midX) < 0.0001 ? x - width / 2 : (rect.midX > 0 ? x - 44 : x + 44 - width)
                return CGRect(x: left, y: y - height / 2, width: width, height: height)
            }
        }
        func fits(_ rects: [CGRect]) -> Bool {
            !rects.contains { $0.intersects(CGRect(x: -24, y: -24, width: 48, height: 48)) }
                && !rects.enumerated().contains { index, rect in
                    rects.dropFirst(index + 1).contains { edgeGap(rect, $0) < 12.0001 }
                }
        }
        if fits(template(initial)) { return (template(initial), initial) }
        var low = initial, high = initial * 2
        while !fits(template(high)) {
            high *= 2
            guard high.isFinite else { return ([], 0) }
        }
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if fits(template(middle)) { high = middle } else { low = middle }
        }
        return (template(high), high)
    }

    static func edgeGap(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let dx = max(0, abs(first.midX - second.midX) - (first.width + second.width) / 2 + 2 * cornerRadius)
        let dy = max(0, abs(first.midY - second.midY) - (first.height + second.height) / 2 + 2 * cornerRadius)
        return hypot(dx, dy) - 2 * cornerRadius
    }

    static func items(count: Int, buttonSize: CGSize, pinnedIndex: Int = 0, angle: CGFloat? = nil) -> [CGRect] {
        guard (1...8).contains(count), buttonSize.width.isFinite, buttonSize.height.isFinite,
            (0..<count).contains(pinnedIndex), angle?.isFinite ?? true,
            buttonSize.width >= 2 * cornerRadius, buttonSize.height >= 2 * cornerRadius else { return [] }
        func template(_ radius: CGFloat) -> [CGRect] {
            guard let angle else { return ring(count: count, radius: radius, buttonSize: buttonSize) }
            let ring = directedRing(count: count, radius: radius, buttonSize: buttonSize, angle: angle)
            guard ring.count == count else { return [] }
            return (0..<count).map { ring[($0 - pinnedIndex + count) % count] }
        }
        let neutral = CGRect(x: -24, y: -24, width: 48, height: 48)
        func fits(_ items: [CGRect]) -> Bool {
            guard items.count == count else { return false }
            let gaps = count > 1 ? items.indices.map { edgeGap(items[$0], items[($0 + 1) % count]) } : [0]
            return (gaps.max()! - gaps.min()!) < 0.1 && !items.contains(where: { $0.intersects(neutral) })
                && !items.enumerated().contains { index, rect in
                    items.dropFirst(index + 1).contains { edgeGap(rect, $0) < 12.0001 }
                }
        }
        var low: CGFloat = 0
        var high = max(buttonSize.width, buttonSize.height) + 48
        while !fits(template(high)) {
            high *= 2
            guard high.isFinite else { return [] }
        }
        for _ in 0..<24 {
            let radius = (low + high) / 2
            if fits(template(radius)) { high = radius }
            else { low = radius }
        }
        return template(high)
    }

    private static func directedRing(count: Int, radius: CGFloat, buttonSize: CGSize, angle: CGFloat) -> [CGRect] {
        let start = angle.truncatingRemainder(dividingBy: 2 * .pi)
        func rect(_ angle: CGFloat) -> CGRect {
            CGRect(x: sin(angle) * radius - buttonSize.width / 2,
                y: -cos(angle) * radius - buttonSize.height / 2,
                width: buttonSize.width, height: buttonSize.height)
        }
        if count <= 2 { return (0..<count).map { rect(start + CGFloat($0) * .pi) } }
        let even = count.isMultiple(of: 2)
        let steps = (even ? count / 2 : count) - 1
        let end = start + (even ? .pi : 2 * .pi)
        func chain(gap: CGFloat) -> [CGFloat]? {
            var angles = [start]
            for _ in 0..<steps {
                let previous = angles[angles.count - 1]
                let first = rect(previous)
                let limit = min(previous + .pi, end)
                var low = previous, high = previous
                // Find the first crossing: horizontal capsules need not have monotonic distance over a semicircle.
                while high < limit && edgeGap(first, rect(high)) < gap {
                    low = high
                    high = min(high + .pi / 32, limit)
                }
                guard edgeGap(first, rect(high)) >= gap else { return nil }
                for _ in 0..<24 {
                    let middle = (low + high) / 2
                    if edgeGap(first, rect(middle)) < gap { low = middle } else { high = middle }
                }
                angles.append((low + high) / 2)
            }
            return angles
        }
        var low: CGFloat = 0, high = radius * 2
        for _ in 0..<28 {
            let gap = (low + high) / 2
            if let angles = chain(gap: gap), let last = angles.last,
                edgeGap(rect(last), rect(end)) >= gap { low = gap }
            else { high = gap }
        }
        guard var angles = chain(gap: low) else { return [] }
        if even { angles += angles.map { $0 + .pi } }
        return angles.map(rect)
    }

    private static func ring(count: Int, radius: CGFloat, buttonSize: CGSize) -> [CGRect] {
        func rect(_ angle: CGFloat) -> CGRect {
            CGRect(x: sin(angle) * radius - buttonSize.width / 2,
                y: -cos(angle) * radius - buttonSize.height / 2,
                width: buttonSize.width, height: buttonSize.height)
        }
        if count <= 2 { return (0..<count).map { rect(CGFloat($0) * .pi) } }
        let even = count.isMultiple(of: 2)
        let steps = count / 2 - (even ? 1 : 0)
        func half(gap: CGFloat) -> [CGFloat]? {
            var angles: [CGFloat] = [0]
            for _ in 0..<steps {
                let previous = angles[angles.count - 1]
                let first = rect(previous)
                guard edgeGap(first, rect(.pi)) >= gap else { return nil }
                var low = previous, high = CGFloat.pi
                for _ in 0..<28 {
                    let angle = (low + high) / 2
                    if edgeGap(first, rect(angle)) < gap { low = angle } else { high = angle }
                }
                angles.append((low + high) / 2)
            }
            return angles
        }
        func closingGap(_ angles: [CGFloat]) -> CGFloat {
            let last = angles[angles.count - 1]
            return edgeGap(rect(last), rect(even ? .pi : 2 * .pi - last))
        }
        guard let initial = half(gap: 0), closingGap(initial) >= 0 else { return [] }
        var low: CGFloat = 0, high = radius * 2
        for _ in 0..<28 {
            let gap = (low + high) / 2
            if let angles = half(gap: gap), closingGap(angles) >= gap { low = gap }
            else { high = gap }
        }
        guard var angles = half(gap: low) else { return [] }
        // Mirror the solved half so every template has an exact vertical axis.
        let reflected = angles.dropFirst().reversed().map { 2 * CGFloat.pi - $0 }
        if even { angles.append(.pi) }
        angles += reflected
        return angles.map(rect)
    }
}
