import AppKit
import Foundation

let snippetTitleFontSize: CGFloat = 13
func floatingButtonWidth(for title: String, accessoryWidth: CGFloat = 0) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: snippetTitleFontSize, weight: .medium)]
    return max(88, ceil((title as NSString).size(withAttributes: attributes).width + 20 + accessoryWidth))
}
func snippetButtonWidth(for titles: [String], characterLimit: Int = 10, accessoryWidth: CGFloat = 0) -> CGFloat {
    titles.map { floatingButtonWidth(for: floatingButtonTitle($0, characterLimit: characterLimit), accessoryWidth: accessoryWidth) }.max() ?? 88
}

func floatingButtonTitle(_ title: String, characterLimit: Int = 10) -> String {
    let singleLine = title.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
    let visible = String(singleLine.prefix(max(1, characterLimit)))
    return visible + (singleLine.count > visible.count ? "…" : "")
}
