import XCTest

@testable import PhrasePerch

final class ProfileEditorViewModelTests: XCTestCase {
    @MainActor
    func testTriggerButtonsKeepOneEntryAndPersistPerApplication() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let profiles = ["first", "second"].map {
            AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.\($0)", fallbackBundlePath: nil), displayName: $0)
        }
        repository.update { $0.profiles = profiles }
        let models = profiles.map {
            ProfileEditorViewModel(profileID: $0.id, repository: repository, editing: ProfileEditingService(repository: repository))
        }
        defer { models.forEach { $0.stop() } }
        let model = models[0]
        model.toggleModifierTrigger()
        XCTAssertEqual(model.displayMode, .modifierClick)
        model.toggleShortcutTrigger()
        XCTAssertEqual(model.displayMode, .both)
        model.toggleModifierTrigger()
        XCTAssertEqual(model.displayMode, .shortcutOnly)
        model.toggleShortcutTrigger()
        XCTAssertEqual(model.displayMode, .shortcutOnly)
        model.toggleModifierTrigger()
        XCTAssertEqual(model.displayMode, .both)
        model.toggleShortcutTrigger()
        XCTAssertEqual(model.displayMode, .modifierClick)
        for mode in DisplayMode.allCases {
            model.displayMode = mode
            XCTAssertEqual(models[1].displayMode, .modifierClick)
            let saved = await repository.flush()
            XCTAssertTrue(saved)
            let readback = try await JSONConfigurationStorage(directory: directory).load()
            XCTAssertEqual(readback.profiles[0].displayMode, mode)
            XCTAssertEqual(readback.profiles[1].displayMode, .modifierClick)
        }
    }

    @MainActor
    func testHeaderCreationUsesCurrentGroupAndBreadcrumbReturnsToRoot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.group", fallbackBundlePath: nil), displayName: "Test")
        repository.update { $0.profiles = [profile] }
        let model = ProfileEditorViewModel(profileID: profile.id, repository: repository, editing: ProfileEditingService(repository: repository))
        defer { model.stop() }
        model.addGroup()
        let parent = try XCTUnwrap(model.nodes.first).id
        model.openGroup(parent)
        model.addGroup()
        let child = try XCTUnwrap(model.nodes.first).id
        model.openGroup(child)
        model.addSnippet()
        XCTAssertEqual(model.groupPath, [parent, child])
        XCTAssertEqual(model.nodes.count, 1)
        XCTAssertEqual(model.nodes.first?.id, model.selectedSnippet?.id)
        model.openGroup(parent)
        XCTAssertEqual(model.groupPath, [parent])
        XCTAssertEqual(model.nodes.map(\.id), [child])
        model.openGroup(nil)
        XCTAssertTrue(model.groupPath.isEmpty)
        XCTAssertEqual(model.nodes.map(\.id), [parent])
        let saved = await repository.flush()
        XCTAssertTrue(saved)
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
        XCTAssertEqual(model.titleIssue, "请填写内容标题")
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
