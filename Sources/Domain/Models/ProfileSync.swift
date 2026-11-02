import Foundation

struct ProfileSync: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var sourceProfileID: UUID
    var isEnabled = true
}
