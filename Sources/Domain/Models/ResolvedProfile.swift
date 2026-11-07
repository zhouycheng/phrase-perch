import Foundation

struct ResolvedProfile: Sendable {
    let profile: AppProfile
    let localNodeIDs: [UUID: UUID]
}
