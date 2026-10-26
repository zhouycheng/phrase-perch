import SwiftUI

struct ContentToolbarButtonLayout: Layout {
    let columns: Int
    private let spacing: CGFloat = 6
    private let rowSpacing: CGFloat = 8
    private let height: CGFloat = 28

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cellWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let minimum = cellWidth * CGFloat(columns) + spacing * CGFloat(columns - 1)
        let rows = (subviews.count + columns - 1) / columns
        return CGSize(width: max(minimum, proposal.width ?? minimum),
            height: CGFloat(rows) * height + CGFloat(max(0, rows - 1)) * rowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = max(0, (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index % columns) * (width + spacing),
                y: bounds.minY + CGFloat(index / columns) * (height + rowSpacing)),
                anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
        }
    }
}
