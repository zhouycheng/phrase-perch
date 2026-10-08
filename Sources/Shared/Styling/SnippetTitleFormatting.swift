import AppKit
import Foundation

let snippetTitleFontSize: CGFloat = 13
func snippetButtonWidth(for titles: [String]) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: snippetTitleFontSize, weight: .medium)]
    let width = titles.map { (floatingButtonTitle($0) as NSString).size(withAttributes: attributes).width }.max() ?? 0
    return max(88, ceil(width + 20))
}

func floatingButtonTitle(_ title: String) -> String {
    let singleLine = title.split(whereSeparator: \.isNewline).joined(separator: " ")
    return String(singleLine.prefix(10)) + (singleLine.count > 10 ? "…" : "")
}
