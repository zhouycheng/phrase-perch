import AppKit
import KeyboardShortcuts
import SwiftUI

enum EditorStyle {
    static let headerHeight: CGFloat = 56
    static let contentInset: CGFloat = 22
    static let background = Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
    static let selectedRow = Color(red: 61 / 255, green: 61 / 255, blue: 61 / 255)
    static let separator = Color.white.opacity(0.13)

    @MainActor static var bodyTextAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
            .paragraphStyle: paragraph]
    }
}
