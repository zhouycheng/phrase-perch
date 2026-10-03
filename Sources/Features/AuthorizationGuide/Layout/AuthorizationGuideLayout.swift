import AppKit
import QuartzCore

func authorizationGuideFrame(settings: CGRect?, visible: CGRect) -> CGRect {
    // ponytail: without AX, use window bounds; place below the window or at its bottom, and allow manual adjustment.
    let width = min(420, settings.map { max(300, $0.width * 0.68 - 28) } ?? 420, visible.width)
    let size = CGSize(width: width, height: min(112, visible.height))
    let x = settings.map { $0.maxX - width - 14 } ?? visible.maxX - width - 16
    let y =
        settings.map {
            $0.minY - size.height - 8 >= visible.minY
                ? $0.minY - size.height - 8 : $0.minY + 12
        } ?? visible.minY + 16
    return CGRect(
        x: max(visible.minX, min(x, visible.maxX - size.width)),
        y: max(visible.minY, min(y, visible.maxY - size.height)), width: size.width, height: size.height)
}
