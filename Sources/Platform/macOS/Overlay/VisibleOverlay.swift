import AppKit
import QuartzCore

struct VisibleOverlay {
    var ownerPID: pid_t
    var layer: Int
    var frame: CGRect
    var alpha: Double
}
