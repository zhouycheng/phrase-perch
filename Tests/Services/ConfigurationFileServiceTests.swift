import XCTest

@testable import PhrasePerch

final class ConfigurationFileServiceTests: XCTestCase {
    @MainActor
    func testImportRequiresConfirmationAndReportsInvalidFilesWithoutChangingConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(storage: StubConfigurationStorage())
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(repository.isReady)
        let dialog = StubConfigurationFileDialog()
        let service = ConfigurationFileService(
            store: repository,
            editing: ProfileEditingService(repository: repository), dialog: dialog)
        let original = repository.configuration
        var imported = AppConfiguration()
        imported.profiles = [
            AppProfile(
                application: ApplicationIdentity(bundleIdentifier: "test.import", fallbackBundlePath: nil),
                displayName: "Imported", buttons: [Snippet(title: "标题", text: "正文")])
        ]
        let url = directory.appendingPathComponent("import.json")
        try JSONEncoder().encode(imported).write(to: url)
        await service.importConfiguration(from: url)
        XCTAssertEqual(repository.configuration, original)
        XCTAssertEqual(dialog.proposedCounts?.profiles, 1)
        XCTAssertEqual(dialog.proposedCounts?.snippets, 1)
        dialog.acceptsReplacement = true
        await service.importConfiguration(from: url)
        XCTAssertEqual(repository.configuration, imported)
        XCTAssertEqual(repository.saveStatus, "已保存")
        try Data("invalid JSON".utf8).write(to: url)
        await service.importConfiguration(from: url)
        XCTAssertEqual(repository.issue?.operation, .importFile)
        XCTAssertEqual(repository.configuration, imported)
    }
}
