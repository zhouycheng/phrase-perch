import XCTest

@testable import PhrasePerch

final class AttachmentImportTests: XCTestCase {
    @MainActor
    private func finishImport(_ model: ProfileEditorViewModel) async throws {
        for _ in 0..<200 where model.isImportingAttachment { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.isImportingAttachment)
    }

    @MainActor
    func testEmptyListDropAndToolbarAppendNamedManagedCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = JSONConfigurationStorage(directory: root.appendingPathComponent("store"))
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.drop", fallbackBundlePath: nil), displayName: "Test")
        try await disk.save(AppConfiguration(profiles: [profile]))
        let urls = [root.appendingPathComponent("first/中文附件.txt"), root.appendingPathComponent("second/中文附件.txt")]
        for (index, url) in urls.enumerated() {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("file \(index)".utf8).write(to: url)
        }
        let store = ConfigurationRepository(storage: disk)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let model = ProfileEditorViewModel(profileID: profile.id, repository: store,
            editing: ProfileEditingService(repository: store), chooseAttachments: { _ in [urls[1]] })
        defer { model.stop() }
        XCTAssertTrue(model.nodes.isEmpty)
        XCTAssertTrue(model.addAttachments(from: [urls[0]]))
        XCTAssertFalse(model.addAttachments(from: [urls[1]]))
        try await finishImport(model)
        model.addAttachments()
        try await finishImport(model)
        XCTAssertEqual(model.profile?.buttons.map(\.title), ["中文附件.txt", "中文附件.txt"])
        XCTAssertEqual(model.nodes.map(\.id), model.profile?.buttons.map(\.id))
        XCTAssertEqual(model.selectedSnippet?.id, model.profile?.buttons.last?.id)
        XCTAssertNil(model.attachmentMessage)
        for url in urls { try FileManager.default.removeItem(at: url) }
        let saved = await store.flush()
        XCTAssertTrue(saved)
        let restored = try await disk.load()
        XCTAssertEqual(restored, store.configuration)
        for (index, file) in restored.attachments.enumerated() {
            let url = try await disk.attachmentURL(file)
            XCTAssertEqual(try Data(contentsOf: url), Data("file \(index)".utf8))
        }
        XCTAssertEqual(Set(restored.attachments.map(\.id)).count, 2)
    }

    @MainActor
    func testMultiFileDropKeepsNestedDestinationAndReportsOnlyFailedFilesAfterNavigation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = JSONConfigurationStorage(directory: root.appendingPathComponent("store"))
        let existing = Snippet(title: "已有文案", text: "正文")
        let child = SnippetGroup(title: "子分组", children: [MenuNode(kind: .snippet, id: existing.id)])
        let parent = SnippetGroup(title: "父分组", children: [MenuNode(kind: .group, id: child.id)])
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.drop-group", fallbackBundlePath: nil),
            displayName: "Test", buttons: [existing], groups: [parent, child], rootNodes: [MenuNode(kind: .group, id: parent.id)])
        try await disk.save(AppConfiguration(profiles: [profile]))
        let first = root.appendingPathComponent("📎 文件.txt"), last = root.appendingPathComponent("last.txt")
        for url in [first, last] { try Data("attachment".utf8).write(to: url) }
        let missing = root.appendingPathComponent("missing.txt")
        let store = ConfigurationRepository(storage: disk)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let model = ProfileEditorViewModel(profileID: profile.id, repository: store, editing: ProfileEditingService(repository: store))
        defer { model.stop() }
        model.openGroup(parent.id); model.openGroup(child.id)
        XCTAssertTrue(model.addAttachments(from: [first, missing, root, last]))
        model.openGroup(nil)
        try await finishImport(model)
        XCTAssertEqual(model.currentGroup, nil)
        XCTAssertNil(model.selectedSnippet)
        XCTAssertEqual(model.profile?.buttons.map(\.title), [existing.title, first.lastPathComponent, last.lastPathComponent])
        XCTAssertEqual(model.profile?.children(of: child.id).map(\.id), model.profile?.buttons.map(\.id))
        XCTAssertTrue(model.attachmentMessage?.contains("missing.txt") == true)
        XCTAssertTrue(model.attachmentMessage?.contains("请选择普通文件") == true)
        XCTAssertFalse(model.attachmentMessage?.contains(first.lastPathComponent) == true)
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }

    @MainActor
    func testDeletedDropTargetsReleaseUncommittedAttachmentCopies() async throws {
        for removeProfile in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let directory = root.appendingPathComponent("store")
            let disk = JSONConfigurationStorage(directory: directory)
            let group = SnippetGroup(title: "目标分组")
            let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.drop-deletion", fallbackBundlePath: nil),
                displayName: "Test", buttons: [], groups: [group], rootNodes: [MenuNode(kind: .group, id: group.id)])
            try await disk.save(AppConfiguration(profiles: [profile]))
            let source = root.appendingPathComponent("file.txt")
            try Data("attachment".utf8).write(to: source)
            let store = ConfigurationRepository(storage: disk)
            for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
            let editing = ProfileEditingService(repository: store)
            let model = ProfileEditorViewModel(profileID: profile.id, repository: store, editing: editing)
            defer { model.stop() }
            model.openGroup(group.id)
            XCTAssertTrue(model.addAttachments(from: [source]))
            if removeProfile { store.update { $0.profiles = [] } }
            else { editing.removeGroup(group.id, in: profile.id) }
            try await finishImport(model)
            XCTAssertTrue(model.attachmentMessage?.contains("目标应用或分组已移除") == true)
            XCTAssertTrue(store.configuration.attachments.isEmpty)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("attachments").path), [])
            let saved = await store.flush()
            XCTAssertTrue(saved)
        }
    }

    @MainActor
    func testDropRejectsEmptyAndRemotePayloadsWithoutChangingConfiguration() async throws {
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.drop-validation", fallbackBundlePath: nil), displayName: "Test")
        let model = ProfileEditorViewModel(profileID: profile.id, repository: store, editing: ProfileEditingService(repository: store))
        defer { model.stop() }
        XCTAssertFalse(model.addAttachments(from: [URL(fileURLWithPath: "/tmp/file.txt")]))
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        store.update { $0.profiles = [profile] }
        let original = store.configuration
        XCTAssertFalse(model.addAttachments(from: []))
        XCTAssertFalse(model.addAttachments(from: [try XCTUnwrap(URL(string: "https://example.com/file.txt"))]))
        XCTAssertFalse(model.isImportingAttachment)
        XCTAssertEqual(store.configuration, original)
        let saved = await store.flush()
        XCTAssertTrue(saved)
    }
}
