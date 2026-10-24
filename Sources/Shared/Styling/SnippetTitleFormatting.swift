import AppKit
import Foundation

let snippetTitleFontSize: CGFloat = 13
func snippetButtonWidth(for titles: [String]) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: snippetTitleFontSize, weight: .medium)]
    let width = titles.map { (floatingButtonTitle($0) as NSString).size(withAttributes: attributes).width }.max() ?? 0
    return min(132, max(88, ceil(width + 20)))
}

func floatingButtonTitle(_ title: String) -> String {
    let singleLine = title.split(whereSeparator: \.isNewline).joined(separator: " ")
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: snippetTitleFontSize, weight: .medium)]
    var visible = String(singleLine.prefix(10))
    var suffix = singleLine.count > visible.count ? "…" : ""
    while !visible.isEmpty && ((visible + suffix) as NSString).size(withAttributes: attributes).width > 112 {
        visible.removeLast()
        suffix = "…"
    }
    return visible + suffix
}
