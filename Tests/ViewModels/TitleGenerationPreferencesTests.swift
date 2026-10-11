import XCTest

@testable import PhrasePerch

final class TitleGenerationPreferencesTests: XCTestCase {
    @MainActor
    func testProviderDraftsSaveOnlyActiveSettingsAndPreserveBothProviders() async throws {
        let stub = try StubCodexCLI()
        defer { stub.cleanup() }
        let directory = stub.directory.appendingPathComponent("configuration")
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        repository.update { $0.preferences.titleModel = "proxy-model" }
        let dependencies = AppDependencies(repository: repository, titleService: TitleGenerationService(codex: stub.runner))
        defer { dependencies.mainWindowViewModel.stop() }
        let model = dependencies.preferencesViewModel
        model.loadTitleSettings()
        model.titleGenerationProvider = .codexCLI
        model.codexExecutablePath = stub.executable.path
        model.titleAPIBaseURL = "invalid inactive draft"
        model.titleModel = ""
        XCTAssertEqual(repository.configuration.preferences.titleGenerationProvider, .cliProxyAPI)
        model.checkCodexEnvironment()
        for _ in 0..<100 where model.isCheckingCodex { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.titleSettingsMessage?.contains("已就绪") == true)
        await model.saveTitleSettings()
        XCTAssertEqual(model.titleSettingsMessage, "设置已保存")
        let saved = try await JSONConfigurationStorage(directory: directory).load()
        XCTAssertEqual(saved.preferences.titleGenerationProvider, .codexCLI)
        XCTAssertEqual(saved.preferences.codexExecutablePath, stub.executable.path)
        XCTAssertEqual(saved.preferences.titleModel, "proxy-model")
        XCTAssertEqual(saved.preferences.titleAPIBaseURL, Preferences.defaultTitleAPIBaseURL)
        model.codexExecutablePath = "/missing/codex"
        await model.saveTitleSettings()
        XCTAssertEqual(repository.configuration.preferences, saved.preferences)
        model.loadTitleSettings()
        model.titleGenerationProvider = .cliProxyAPI
        await model.saveTitleSettings()
        XCTAssertEqual(repository.configuration.preferences.titleGenerationProvider, .cliProxyAPI)
        XCTAssertEqual(repository.configuration.preferences.codexExecutablePath, stub.executable.path)
        XCTAssertEqual(repository.configuration.preferences.titleModel, "proxy-model")
        model.loadTitleSettings()
        XCTAssertEqual(model.codexExecutablePath, stub.executable.path)
    }

    @MainActor
    func testEditingCodexPathOrLeavingSettingsCancelsEnvironmentCheck() async throws {
        let stub = try StubCodexCLI(login: "exec /bin/sleep 20")
        defer { stub.cleanup() }
        let repository = ConfigurationRepository(directory: stub.directory.appendingPathComponent("configuration"))
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let dependencies = AppDependencies(repository: repository, titleService: TitleGenerationService(codex: stub.runner))
        defer { dependencies.mainWindowViewModel.stop() }
        let model = dependencies.preferencesViewModel
        model.titleGenerationProvider = .codexCLI
        model.codexExecutablePath = stub.executable.path
        model.checkCodexEnvironment()
        try await Task.sleep(for: .milliseconds(50))
        model.codexExecutablePath = "/new/codex"
        XCTAssertFalse(model.isCheckingCodex)
        model.codexExecutablePath = stub.executable.path
        model.checkCodexEnvironment()
        model.cancelModelsRead()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.isCheckingCodex)
        XCTAssertNil(model.titleSettingsMessage)
    }

    @MainActor
    func testModelRefreshPreservesSelectionAndSettingsSaveRoundTrips() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        repository.update { $0.preferences.titleModel = "saved-model" }
        let dependencies = AppDependencies(repository: repository, titleService: StubTitleURLProtocol.service { _ in
            (200, Data(#"{"data":[{"id":"new-model"}]}"#.utf8))
        })
        defer { dependencies.mainWindowViewModel.stop() }
        let model = dependencies.preferencesViewModel
        model.loadTitleSettings()
        XCTAssertEqual(model.titleModel, "saved-model")
        model.readTitleModels()
        for _ in 0..<100 where model.isReadingModels { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.titleModels, ["new-model"])
        XCTAssertEqual(model.titleModel, "saved-model")
        model.titleAPIBaseURL = "http://localhost:9000/v1/"
        model.titleModel = "new-model"
        XCTAssertEqual(repository.configuration.preferences.titleModel, "saved-model", "Draft settings apply only on save")
        await model.saveTitleSettings()
        XCTAssertEqual(model.titleSettingsMessage, "设置已保存")
        let saved = try await JSONConfigurationStorage(directory: directory).load()
        XCTAssertEqual(saved.preferences.titleAPIBaseURL, "http://localhost:9000/v1")
        XCTAssertEqual(saved.preferences.titleModel, "new-model")
        model.titleAPIBaseURL = "https://example.com/v1"
        await model.saveTitleSettings()
        XCTAssertTrue(model.titleSettingsMessage?.contains("本机服务地址") == true)
        XCTAssertEqual(repository.configuration.preferences, saved.preferences)
    }

    @MainActor
    func testAddressEditAndLeavingSettingsDiscardOldModelList() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let dependencies = AppDependencies(repository: repository, titleService: StubTitleURLProtocol.service { _ in
            Thread.sleep(forTimeInterval: 0.15)
            return (200, Data(#"{"data":[{"id":"old-model"}]}"#.utf8))
        })
        defer { dependencies.mainWindowViewModel.stop() }
        let model = dependencies.preferencesViewModel
        model.readTitleModels()
        model.titleAPIBaseURL = "http://localhost:9000/v1"
        XCTAssertFalse(model.isReadingModels)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertTrue(model.titleModels.isEmpty)
        model.readTitleModels()
        model.cancelModelsRead()
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertTrue(model.titleModels.isEmpty)
        XCTAssertNil(model.titleSettingsMessage)
    }
}
