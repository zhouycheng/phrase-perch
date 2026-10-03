import CoreGraphics
import Foundation

func floatingButtonTitle(_ title: String) -> String {
    String(title.prefix(4)) + (title.count > 4 ? "…" : "")
}
