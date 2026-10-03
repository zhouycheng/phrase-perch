import CoreGraphics
import Foundation

enum MenuAnchorMode: String, Codable, CaseIterable, Sendable {
    case mouse, caret
    var title: String { self == .mouse ? "鼠标位置" : "输入光标位置" }
}
