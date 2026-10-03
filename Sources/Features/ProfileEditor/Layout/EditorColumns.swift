import AppKit
import KeyboardShortcuts
import SwiftUI

struct EditorColumns {
    static let navigation: CGFloat = 68
    let sidebar: CGFloat
    let ring: CGFloat
    let editor: CGFloat

    init(width: CGFloat) {
        let shrink = min(1, max(0, (960 - width) / 80))
        sidebar = 200 - 10 * shrink
        editor = width < 960 ? 280 - 20 * shrink : min(420, 280 + (width - 960) / 3)
        ring = max(0, width - Self.navigation - sidebar - editor - 3)
    }
}
