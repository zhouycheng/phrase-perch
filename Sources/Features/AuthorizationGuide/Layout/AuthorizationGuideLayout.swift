import AppKit

func authorizationGuideFrame(settings: CGRect?, visible: CGRect) -> CGRect {
    let intersection = settings?.intersection(visible)
    let area = intersection.flatMap { $0.isNull || $0.isEmpty ? nil : $0 } ?? visible
    let width = min(420, settings.map { max(300, $0.width * 0.68 - 28) } ?? 420, area.width)
    let size = CGSize(width: width, height: min(112, area.height))
    // shortcut: window proportions approximate the content area; use AX bounds when permission-independent discovery becomes available.
    let center = settings.map { CGPoint(x: $0.minX + $0.width * 0.66, y: $0.minY + $0.height * 0.20) }
        ?? CGPoint(x: visible.maxX - width / 2 - 16, y: visible.minY + size.height / 2 + 16)
    return CGRect(x: max(area.minX, min(center.x - size.width / 2, area.maxX - size.width)),
        y: max(area.minY, min(center.y - size.height / 2, area.maxY - size.height)),
        width: size.width, height: size.height)
}
