import XCTest

@testable import PhrasePerch

final class ProfileEditorViewModelTests: XCTestCase {
    @MainActor
    func testGeneratedTitleUsesExistingSaveFlowAndFailurePreservesOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let snippet = Snippet(title: "原标题", text: "解释代码的实现过程")
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.title", fallbackBundlePath: nil), displayName: "Test", buttons: [snippet])
        repository.update { $0.profiles = [profile] }
        let requested = expectation(description: "Only one generation request")
        requested.assertForOverFulfill = true
        let service = StubTitleURLProtocol.service { _ in
            requested.fulfill()
            return (200, Data(#"{"choices":[{"message":{"content":"代码解释"}}]}"#.utf8))
        }
        let model = ProfileEditorViewModel(
            profileID: profile.id, repository: repository, editing: ProfileEditingService(repository: repository), titleService: service)
        defer { model.stop() }
        XCTAssertFalse(model.canGenerateTitle)
        repository.update { $0.preferences.titleModel = "test-model" }
        XCTAssertTrue(model.canGenerateTitle)
        model.generateTitle()
        model.generateTitle()
        for _ in 0..<100 where model.isGeneratingTitle { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.selectedSnippet?.title, "代码解释")
        XCTAssertNil(model.titleGenerationMessage)
        let saved = await repository.flush()
        XCTAssertTrue(saved)
        let readback = try await JSONConfigurationStorage(directory: directory).load()
        XCTAssertEqual(readback.profiles.first?.buttons.first?.title, "代码解释")
        XCTAssertEqual(readback.preferences.titleModel, "test-model")
        let failed = ProfileEditorViewModel(
            profileID: profile.id, repository: repository, editing: ProfileEditingService(repository: repository),
            titleService: StubTitleURLProtocol.service { _ in (403, Data()) })
        defer { failed.stop() }
        failed.generateTitle()
        for _ in 0..<100 where failed.isGeneratingTitle { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(failed.selectedSnippet?.title, "代码解释")
        XCTAssertTrue(failed.titleGenerationMessage?.contains("鉴权") == true)
        failed.setText(" \n ", id: snippet.id)
        XCTAssertFalse(failed.canGenerateTitle)
        XCTAssertNil(failed.titleGenerationMessage)
        await fulfillment(of: [requested], timeout: 1)
    }

    @MainActor
    func testEditingSelectionDeletionAndStopInvalidatePendingTitle() async throws {
        for action in ["title", "text", "selection", "page", "deletion", "stop", "settings", "import"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let repository = ConfigurationRepository(directory: directory)
            for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
            let snippets = (0..<10).map { Snippet(title: "原标题\($0)", text: "正文\($0)") }
            let profile = AppProfile(
                application: ApplicationIdentity(bundleIdentifier: "test.pending", fallbackBundlePath: nil), displayName: "Test", buttons: snippets)
            repository.update { $0.profiles = [profile]; $0.preferences.titleModel = "test-model" }
            let started = expectation(description: "Request started for \(action)")
            let model = ProfileEditorViewModel(
                profileID: profile.id, repository: repository, editing: ProfileEditingService(repository: repository),
                titleService: StubTitleURLProtocol.service { _ in
                    started.fulfill()
                    Thread.sleep(forTimeInterval: 0.15)
                    return (200, Data(#"{"choices":[{"message":{"content":"过期标题"}}]}"#.utf8))
                })
            defer { model.stop() }
            model.generateTitle()
            await fulfillment(of: [started], timeout: 1)
            switch action {
            case "title": model.setTitle("手动标题", id: snippets[0].id)
            case "text": model.setText("新正文", id: snippets[0].id)
            case "selection": model.select(snippets[1].id)
            case "page": model.showPage(1)
            case "deletion": model.requestDeletion(snippets[0].id); model.confirmDeletion(snippets[0].id)
            case "settings": repository.update { $0.preferences.titleModel = "new-model" }
            case "import": repository.update { $0.profiles[0].buttons[0].text = "导入的新正文" }
            default: model.stop()
            }
            XCTAssertFalse(model.isGeneratingTitle, action)
            try await Task.sleep(for: .milliseconds(180))
            XCTAssertFalse(repository.configuration.profiles[0].buttons.contains { $0.title == "过期标题" }, action)
            XCTAssertNil(model.titleGenerationMessage, action)
            if action == "title" { XCTAssertEqual(model.title(snippets[0].id), "手动标题") }
        }
    }

    @MainActor
    func testChangingProfileNavigationAndClosingWindowCancelGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let profiles = (0..<2).map { index in
            AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.title.\(index)", fallbackBundlePath: nil),
                displayName: "Test", buttons: [Snippet(title: "原标题", text: "正文")])
        }
        repository.update { $0.profiles = profiles; $0.preferences.titleModel = "test-model" }
        let dependencies = AppDependencies(repository: repository, titleService: StubTitleURLProtocol.service { _ in
            Thread.sleep(forTimeInterval: 0.15)
            return (200, Data(#"{"choices":[{"message":{"content":"过期标题"}}]}"#.utf8))
        })
        defer { dependencies.mainWindowViewModel.stop() }
        let window = dependencies.mainWindowViewModel
        let first = try XCTUnwrap(window.selectedEditor)
        first.generateTitle()
        window.selectProfile(profiles[1].id)
        XCTAssertFalse(first.isGeneratingTitle)
        let second = try XCTUnwrap(window.selectedEditor)
        second.generateTitle()
        window.page = .settings
        XCTAssertFalse(second.isGeneratingTitle)
        window.page = .home
        second.generateTitle()
        dependencies.mainWindow.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertFalse(second.isGeneratingTitle)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertTrue(repository.configuration.profiles.allSatisfy { $0.buttons[0].title == "原标题" })
    }

    @MainActor
    func testEditingCommandsUseIDsAndKeepSelectionAfterConfirmation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let snippets = (0..<10).map { Snippet(title: "标题\($0)", text: "正文\($0)") }
        let profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.editing", fallbackBundlePath: nil),
            displayName: "Test", buttons: snippets)
        repository.update { $0.profiles = [profile] }
        let model = ProfileEditorViewModel(
            profileID: profile.id, repository: repository,
            editing: ProfileEditingService(repository: repository))
        defer { model.stop() }
        model.showPage(1)
        XCTAssertEqual(model.session.selectedID, snippets[8].id)
        model.duplicate(snippets[8].id)
        let copy = try XCTUnwrap(model.selectedSnippet)
        XCTAssertEqual(copy.title, "标题8 副本")
        model.move(copy.id, by: -1)
        XCTAssertEqual(model.ids[9], copy.id)
        model.requestDeletion(copy.id)
        model.confirmDeletion(snippets[0].id)
        XCTAssertTrue(model.ids.contains(copy.id))
        model.confirmDeletion(copy.id)
        XCTAssertFalse(model.ids.contains(copy.id))
        XCTAssertEqual(model.session.selectedID, snippets[9].id)
        let before = repository.configuration
        model.setTitle("失效操作", id: copy.id)
        model.move(UUID(), by: 1)
        XCTAssertEqual(repository.configuration, before)
        model.setTitle("", id: snippets[9].id)
        XCTAssertEqual(repository.saveStatus, "待补全")
        XCTAssertEqual(model.titleIssue, "请填写文案标题")
        model.setTitle("补齐", id: snippets[9].id)
        let saved = await repository.flush()
        XCTAssertTrue(saved)
    }

    @MainActor
    func testMainWindowKeepsIndependentEditorSessionsAndRemovesDeletedProfiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let profiles = (0..<2).map { index in
            AppProfile(
                application: ApplicationIdentity(bundleIdentifier: "test.profile.\(index)", fallbackBundlePath: nil),
                displayName: "Test", buttons: (0..<10).map { Snippet(title: "标题\($0)", text: "正文") })
        }
        repository.update { $0.profiles = profiles }
        let editing = ProfileEditingService(repository: repository)
        let authorization = AuthorizationService(store: repository, guide: StubAuthorizationGuide())
        let model = MainWindowViewModel(
            repository: repository, editing: editing,
            files: ConfigurationFileService(store: repository, editing: editing, dialog: StubConfigurationFileDialog()),
            authorization: authorization)
        defer { model.stop() }
        model.selectedEditor?.showPage(1)
        let firstSelection = model.selectedEditor?.session.selectedID
        model.selectProfile(profiles[1].id)
        XCTAssertEqual(model.selectedEditor?.session.page, 0)
        model.selectedEditor?.select(profiles[1].buttons[3].id)
        model.selectProfile(profiles[0].id)
        XCTAssertEqual(model.selectedEditor?.session.selectedID, firstSelection)
        model.requestDeletion(profiles[0].id)
        model.cancelDeletion()
        XCTAssertEqual(model.profiles.count, 2)
        model.requestDeletion(profiles[0].id)
        model.confirmDeletion(profiles[0].id)
        XCTAssertEqual(model.selectedProfile, profiles[1].id)
        XCTAssertEqual(model.selectedEditor?.session.selectedID, profiles[1].buttons[3].id)
        model.selectProfile(profiles[0].id)
        XCTAssertEqual(model.selectedProfile, profiles[1].id)
    }

    @MainActor
    func testRepositoryNotifiesMultipleSubscribersAndUnsubscribesIndependently() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        var first = 0
        var second = 0
        let token = repository.observe { first += 1 }
        let other = repository.observe { second += 1 }
        repository.update { $0.preferences.isEnabled = false }
        repository.removeObserver(token)
        repository.update { $0.preferences.isEnabled = true }
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        repository.removeObserver(other)
    }
}
