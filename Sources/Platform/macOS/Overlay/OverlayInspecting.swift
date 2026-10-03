import Foundation

@MainActor
protocol OverlayInspecting {
    func hasOverlay(in frame: CGRect) -> Bool
}
