import XCTest

@testable import PhrasePerch

final class ConfigurationStorageInjectionTests: XCTestCase {
    @MainActor
    func testInjectedStorageFailureRetainsDraftAndRetryPersistsIt() async throws {
        let storage = StubConfigurationStorage()
        let repository = ConfigurationRepository(storage: storage)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        await storage.setSaveFailure(true)
        repository.update { $0.preferences.isEnabled = false }
        let failed = await repository.flush()
        XCTAssertFalse(failed)
        XCTAssertEqual(repository.saveIssue?.operation, .save)
        XCTAssertFalse(repository.configuration.preferences.isEnabled)
        await storage.setSaveFailure(false)
        let retried = await repository.flush()
        XCTAssertTrue(retried)
        let persisted = await storage.load()
        XCTAssertFalse(persisted.preferences.isEnabled)
        XCTAssertNil(repository.saveIssue)
    }
}
