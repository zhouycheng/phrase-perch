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
        let minimumRadius = max(88, (buttonWidth + 6) / sqrt(3))
        let canvasSize = CGSize(
            width: max(size.width, minimumRadius * 2 + buttonWidth + 4),
            height: max(size.height, minimumRadius * 2 + buttonSize.height + 48))
        self.canvasSize = canvasSize
        let radius = max(0, min(140,
            (canvasSize.width - buttonWidth - 4) / 2,
            (canvasSize.height - buttonSize.height - 48) / 2))
        items = CircularButtonLayout.items(count: count, radius: radius, buttonSize: buttonSize).map {
            $0.offsetBy(dx: canvasSize.width / 2, dy: canvasSize.height / 2)
        }
        deletionRect = CGRect(x: canvasSize.width / 2 - 30,
            y: canvasSize.height / 2 + radius + buttonSize.height / 2 + 4, width: 60, height: 20)
    }
}
