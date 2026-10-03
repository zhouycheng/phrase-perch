import Foundation

@MainActor
final class ProfileEditingService {
    let repository: ConfigurationRepository
    init(repository: ConfigurationRepository) { self.repository = repository }

    func editProfile(_ id: UUID, _ change: (inout AppProfile) -> Void) {
        guard repository.isReady else { return }
        repository.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: { $0.id == id }) else { return }
            change(&configuration.profiles[index])
        }
    }

    func removeProfile(_ id: UUID) {
        guard repository.isReady else { return }
        repository.update { $0.profiles.removeAll { $0.id == id } }
    }

    func addProfile(_ profile: AppProfile) -> Bool {
        guard repository.isReady,
            !repository.configuration.profiles.contains(where: { $0.application.key == profile.application.key })
        else { return false }
        repository.update { $0.profiles.append(profile) }
        return true
    }

    func editSnippet(profileID: UUID, snippetID: UUID, _ change: (inout Snippet) -> Void) {
        editProfile(profileID) { profile in
            guard let index = profile.buttons.firstIndex(where: { $0.id == snippetID }) else { return }
            change(&profile.buttons[index])
        }
    }

    func addSnippet(to profileID: UUID) -> UUID? {
        var created: UUID?
        editProfile(profileID) { profile in
            let snippet = Snippet(title: "新文案", text: "在这里填写要插入的内容。")
            profile.buttons.append(snippet)
            created = snippet.id
        }
        return created
    }

    func duplicateSnippet(_ id: UUID, in profileID: UUID) -> UUID? {
        var created: UUID?
        editProfile(profileID) { profile in
            guard var snippet = profile.buttons.first(where: { $0.id == id }) else { return }
            snippet.id = UUID()
            snippet.title += " 副本"
            profile.buttons.append(snippet)
            created = snippet.id
        }
        return created
    }

    func moveSnippet(_ id: UUID, in profileID: UUID, by distance: Int) {
        editProfile(profileID) { profile in
            guard let index = profile.buttons.firstIndex(where: { $0.id == id }),
                profile.buttons.indices.contains(index + distance)
            else { return }
            profile.buttons.swapAt(index, index + distance)
        }
    }

    func removeSnippet(_ id: UUID, in profileID: UUID) -> Int? {
        var removed: Int?
        editProfile(profileID) { profile in
            guard let index = profile.buttons.firstIndex(where: { $0.id == id }) else { return }
            profile.buttons.remove(at: index)
            removed = index
        }
        return removed
    }
}
