import XCTest

@testable import PhrasePerch

final class ProfileEditorViewModelTests: XCTestCase {
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
