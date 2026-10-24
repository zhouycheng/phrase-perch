import CoreGraphics

struct EditorRingLayout {
    static let buttonSize = CGSize(width: 88, height: 36)
    let items: [CGRect]
    let canvasSize: CGSize
    let deletionRect: CGRect

    static func edgeGap(_ first: CGRect, _ second: CGRect) -> CGFloat {
        CircularButtonLayout.edgeGap(first, second)
    }

    init(size: CGSize, count: Int, buttonWidth: CGFloat = Self.buttonSize.width) {
        guard count > 0, count <= SnippetEditorSession.pageSize else {
            items = []
            canvasSize = size
            deletionRect = .zero
            return
        }
        let buttonSize = CGSize(width: buttonWidth, height: Self.buttonSize.height)
        let ring = CircularButtonLayout.items(count: count, buttonSize: buttonSize)
        let bounds = ring.reduce(CGRect(x: -24, y: -24, width: 48, height: 48)) { $0.union($1) }
        let canvasSize = CGSize(
            width: max(size.width, max(abs(bounds.minX), abs(bounds.maxX)) * 2 + 4),
            height: max(size.height, max(abs(bounds.minY), abs(bounds.maxY)) * 2 + 48))
        self.canvasSize = canvasSize
        items = ring.map {
            $0.offsetBy(dx: canvasSize.width / 2, dy: canvasSize.height / 2)
        }
        deletionRect = CGRect(x: canvasSize.width / 2 - 30,
            y: canvasSize.height / 2 + bounds.maxY + 4, width: 60, height: 20)
    }
}
