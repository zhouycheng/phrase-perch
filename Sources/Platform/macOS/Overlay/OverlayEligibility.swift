import AppKit
import QuartzCore

func hasForeignOverlay(
    _ windows: [VisibleOverlay], ownPID: pid_t, targetPID: pid_t? = nil,
    menuFrame: CGRect, screens: [CGRect] = []
) -> Bool {
    windows.contains {
        $0.ownerPID != ownPID && $0.ownerPID != targetPID && $0.layer > 0 && $0.alpha > 0.05 && $0.frame.width >= 48
            && $0.frame.height >= 48 && $0.frame.intersects(menuFrame) && !screens.contains(where: $0.frame.contains)
    }
}
