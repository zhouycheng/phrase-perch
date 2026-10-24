import Foundation

struct SnippetGroup: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var isEnabled = true
    var children: [MenuNode] = []
}
