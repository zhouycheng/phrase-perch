import Foundation

@MainActor
final class PreferencesService {
    private let repository: ConfigurationRepository
    init(repository: ConfigurationRepository) { self.repository = repository }
    func update(_ change: (inout Preferences) -> Void) {
        guard repository.isReady else { return }
        repository.update { change(&$0.preferences) }
    }
}
