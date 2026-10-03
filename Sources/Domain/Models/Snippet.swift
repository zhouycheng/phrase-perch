import CoreGraphics
import Foundation

struct Snippet: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var text: String
    var isEnabled = true
}
