import Foundation

extension ProfileEditingService {
    func canSync(_ sourceID: UUID, to profileID: UUID) -> Bool {
        guard repository.isReady,
            let index = repository.configuration.profiles.firstIndex(where: { $0.id == profileID }) else { return false }
        var configuration = repository.configuration
        configuration.profiles[index].syncs.append(ProfileSync(sourceProfileID: sourceID))
        return (try? configuration.validateSyncReferences()) != nil
    }

    func addSync(from sourceID: UUID, to profileID: UUID, group: UUID?) throws -> UUID {
        guard repository.isReady,
            let index = repository.configuration.profiles.firstIndex(where: { $0.id == profileID }) else {
            throw InputFailure("目标应用已移除")
        }
        var configuration = repository.configuration
        guard group == nil || configuration.profiles[index].groups.contains(where: { $0.id == group }) else {
            throw InputFailure("目标分组已移除")
        }
        let sync = ProfileSync(sourceProfileID: sourceID)
        configuration.profiles[index].syncs.append(sync)
        configuration.profiles[index].setChildren(configuration.profiles[index].children(of: group)
            + [MenuNode(kind: .sync, id: sync.id)], of: group)
        try configuration.validateSyncReferences()
        try configuration.profiles[index].validateHierarchy()
        repository.update { $0 = configuration }
        return sync.id
    }

    func editSync(_ id: UUID, in profileID: UUID, enabled: Bool) {
        editProfile(profileID) { profile in
            guard let index = profile.syncs.firstIndex(where: { $0.id == id }) else { return }
            profile.syncs[index].isEnabled = enabled
        }
    }
}
