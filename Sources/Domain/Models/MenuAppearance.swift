import Foundation

enum MenuAppearance: String, Codable, CaseIterable, Sendable {
    case matte, glass, clearGlass

    var title: String {
        switch self {
        case .matte: "深色哑光"
        case .glass: "液态玻璃 · 标准"
        case .clearGlass: "液态玻璃 · 清透"
        }
    }
}
