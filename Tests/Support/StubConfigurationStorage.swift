import Foundation

@testable import PhrasePerch

actor StubConfigurationStorage: ConfigurationStorage {
    private var configuration = AppConfiguration()
    private var shouldFailSave = false
    private(set) var saves = 0
    func setSaveFailure(_ fail: Bool) { shouldFailSave = fail }
    func load() -> AppConfiguration { configuration }
    func latestBackup() -> AppConfiguration { configuration }
    func decode(_ data: Data) throws -> AppConfiguration { try JSONDecoder().decode(AppConfiguration.self, from: data) }
    func save(_ value: AppConfiguration) throws {
        saves += 1
        if shouldFailSave { throw InputFailure("injected disk failure") }
        try value.validate()
        configuration = value
    }
}
