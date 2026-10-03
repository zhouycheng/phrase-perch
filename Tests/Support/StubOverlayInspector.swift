import Foundation

@testable import PhrasePerch

@MainActor
struct StubOverlayInspector: OverlayInspecting {
    var blocksMenu = false
    func hasOverlay(in frame: CGRect) -> Bool { blocksMenu }
}
