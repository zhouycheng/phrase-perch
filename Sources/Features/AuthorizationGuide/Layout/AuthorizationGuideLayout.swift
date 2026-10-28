import AppKit

func authorizationGuideFrame(settings: CGRect?, visible: CGRect) -> CGRect {
    let size = CGSize(width: min(420, visible.width), height: min(112, visible.height))
    guard let settings else {
        return clampedAuthorizationGuideFrame(CGRect(
            x: visible.maxX - size.width - 12, y: visible.minY + 12,
            width: size.width, height: size.height), visible: visible)
    }
    let origins = [
        CGPoint(x: settings.midX - size.width / 2, y: settings.minY - size.height - 12),
        CGPoint(x: settings.maxX + 12, y: settings.midY - size.height / 2),
        CGPoint(x: settings.minX - size.width - 12, y: settings.midY - size.height / 2),
        CGPoint(x: settings.midX - size.width / 2, y: settings.maxY + 12),
    ]
    for origin in origins {
        let candidate = clampedAuthorizationGuideFrame(CGRect(origin: origin, size: size), visible: visible)
        if !candidate.intersects(settings.insetBy(dx: -11, dy: -11)) { return candidate }
    }
    return clampedAuthorizationGuideFrame(CGRect(
        x: settings.minX + 12, y: settings.maxY - size.height - 12,
        width: size.width, height: size.height), visible: visible)
}

func clampedAuthorizationGuideFrame(_ frame: CGRect, visible: CGRect) -> CGRect {
    let size = CGSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
    return CGRect(x: max(visible.minX, min(frame.minX, visible.maxX - size.width)),
        y: max(visible.minY, min(frame.minY, visible.maxY - size.height)), width: size.width, height: size.height)
}
