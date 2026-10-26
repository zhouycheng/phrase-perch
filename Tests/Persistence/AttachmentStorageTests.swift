import AppKit
import XCTest
@testable import PhrasePerch

final class AttachmentStorageTests: XCTestCase {
    private func profile(_ snippets: [Snippet]) -> AppProfile {
        AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.attachments", fallbackBundlePath: nil),
            displayName: "附件测试", buttons: snippets)
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testVersionOneMigratesTextPreferencesAndPreservesOriginalBackup() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = AppConfiguration(profiles: [profile([Snippet(title: "原文", text: "正文 👩‍💻\n")])])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["schemaVersion"] = 1
        var profiles = object["profiles"] as! [[String: Any]]
        var buttons = profiles[0]["buttons"] as! [[String: Any]]
        buttons[0].removeValue(forKey: "content"); buttons[0]["text"] = "正文 👩‍💻\n"
        profiles[0]["buttons"] = buttons; object["profiles"] = profiles
        var preferences = object["preferences"] as! [String: Any]
        preferences.removeValue(forKey: "menuTitleCharacterLimit"); object["preferences"] = preferences
        let legacy = try JSONSerialization.data(withJSONObject: object)
        try legacy.write(to: root.appendingPathComponent("configuration.json"))
        let disk = JSONConfigurationStorage(directory: root)
        let restored = try await disk.load()
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.schemaVersion, 2)
        XCTAssertEqual(restored.preferences.menuTitleCharacterLimit, 10)
        let backups = try await disk.backups()
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), legacy)
        var invalid = original
        invalid.preferences.menuTitleCharacterLimit = 31
        XCTAssertThrowsError(try invalid.validate())
    }
    func testManagedCopySurvivesSourceDeletionAndRespectsBackupLeaseAndClipboardReferences() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("源文件.txt")
        try Data("测试附件".utf8).write(to: source)
        let disk = JSONConfigurationStorage(directory: root.appendingPathComponent("store"))
        let file = try await disk.importAttachment(from: source)
        let snippet = Snippet(title: "文件", content: .attachment(file))
        var config = AppConfiguration(profiles: [profile([snippet])])
        try await disk.save(config)
        try FileManager.default.removeItem(at: source)
        let url = try await disk.retainAttachment(file)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "测试附件")
        config.profiles[0].buttons = []; config.profiles[0].rootNodes = []
        try await disk.save(config)
        await disk.pruneAttachments(retaining: [], clipboardURLs: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        for count in 1...4 { config.preferences.menuTitleCharacterLimit = count; try await disk.save(config) }
        await disk.pruneAttachments(retaining: [], clipboardURLs: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        await disk.releaseAttachment(file.id)
        await disk.pruneAttachments(retaining: [], clipboardURLs: [url])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        await disk.pruneAttachments(retaining: [], clipboardURLs: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testPackageRoundTripRemapsSharedAssetsAndSupportsReplacingExport() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("notes.txt")
        try Data("attachment bytes".utf8).write(to: source)
        let disk = JSONConfigurationStorage(directory: root.appendingPathComponent("source"))
        let file = try await disk.importAttachment(from: source)
        let config = AppConfiguration(profiles: [profile([
            Snippet(title: "附件一", content: .attachment(file)), Snippet(title: "附件二", content: .attachment(file)),
            Snippet(title: "文案", text: "正文")])])
        try await disk.save(config)
        let package = root.appendingPathComponent("backup.phraseperch")
        try await disk.export(config, to: package)
        try await disk.export(config, to: package)
        let target = JSONConfigurationStorage(directory: root.appendingPathComponent("destination"))
        try await target.save(AppConfiguration())
        let cancelled = try await target.readImport(package)
        await target.discardImport(cancelled)
        let prepared = try await target.readImport(package)
        let imported = try XCTUnwrap(prepared.configuration.attachments.first)
        XCTAssertNotEqual(imported.id, file.id)
        XCTAssertEqual(Set(prepared.configuration.attachments.map(\.id)).count, 1)
        try await target.commitImport(prepared)
        let loaded = try await target.load()
        XCTAssertEqual(loaded, prepared.configuration)
        let importedURL = try await target.attachmentURL(imported)
        XCTAssertEqual(try Data(contentsOf: importedURL), Data("attachment bytes".utf8))
        XCTAssertEqual(loaded.profiles[0].buttons.map(\.id), config.profiles[0].buttons.map(\.id))
    }
    func testPackageRejectsMissingFilesLinksAndTraversalWithoutReplacingConfiguration() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt")
        try Data("private bytes".utf8).write(to: source)
        let disk = JSONConfigurationStorage(directory: root.appendingPathComponent("store"))
        let file = try await disk.importAttachment(from: source)
        let config = AppConfiguration(profiles: [profile([Snippet(title: "附件", content: .attachment(file))])])
        try await disk.save(config)
        let package = root.appendingPathComponent("backup.phraseperch")
        try await disk.export(config, to: package)
        let asset = package.appendingPathComponent("attachments/\(file.id.uuidString)/\(file.fileName)")
        try FileManager.default.removeItem(at: asset)
        do { _ = try await disk.readImport(package); XCTFail("Missing asset accepted") } catch {}
        try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: source)
        do { _ = try await disk.readImport(package); XCTFail("Linked asset accepted") } catch {}
        var malformed = config
        malformed.profiles[0].buttons[0].content = .attachment(AttachmentReference(fileName: "../file.txt", byteCount: 13))
        try JSONEncoder().encode(malformed).write(to: package.appendingPathComponent("configuration.json"))
        do { _ = try await disk.readImport(package); XCTFail("Traversal accepted") } catch {}
        let loaded = try await disk.load()
        XCTAssertEqual(loaded, config)
        do { _ = try await disk.importAttachment(from: root); XCTFail("Directory accepted") } catch {}
    }
    @MainActor
    func testEditingSharesCopiesAndFailedReplacementPreservesAttachmentAndTitle() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = JSONConfigurationStorage(directory: root.appendingPathComponent("store"))
        let original = profile([])
        try await disk.save(AppConfiguration(profiles: [original]))
        let repository = ConfigurationRepository(storage: disk)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let editing = ProfileEditingService(repository: repository)
        let source = root.appendingPathComponent("example.txt")
        try Data("first".utf8).write(to: source)
        let id = try await editing.addAttachment(from: source, to: original.id)
        let created = try XCTUnwrap(repository.configuration.profiles[0].buttons.first)
        let originalFile = try XCTUnwrap(created.attachment)
        let originalURL = try await disk.attachmentURL(originalFile)
        XCTAssertEqual(created.title, "example.txt")
        editing.editSnippet(profileID: original.id, snippetID: id) { $0.title = "自定义标题" }
        let copiedID = try XCTUnwrap(editing.duplicateSnippet(id, in: original.id))
        XCTAssertEqual(repository.configuration.profiles[0].buttons[1].attachment, created.attachment)
        do { try await editing.replaceAttachment(id, in: original.id, from: root); XCTFail("Directory accepted") } catch {}
        XCTAssertEqual(repository.configuration.profiles[0].buttons[0].attachment, created.attachment)
        try Data("second".utf8).write(to: source)
        try await editing.replaceAttachment(id, in: original.id, from: source)
        XCTAssertEqual(repository.configuration.profiles[0].buttons[0].title, "自定义标题")
        XCTAssertNotEqual(repository.configuration.profiles[0].buttons[0].attachment?.id, created.attachment?.id)
        XCTAssertNotNil(editing.removeSnippet(copiedID, in: original.id))
        let saved = await repository.flush()
        XCTAssertTrue(saved)
        for _ in 0..<50 where FileManager.default.fileExists(atPath: originalURL.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    }
    func testDiskCopyAndImportCommitFailuresPreserveExistingData() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt")
        try Data("source".utf8).write(to: source)
        let blocked = root.appendingPathComponent("blocked")
        try Data("preserved".utf8).write(to: blocked)
        let blockedDisk = JSONConfigurationStorage(directory: blocked)
        do { _ = try await blockedDisk.importAttachment(from: source); XCTFail("Disk copy failure expected") } catch {}
        XCTAssertEqual(try String(contentsOf: blocked, encoding: .utf8), "preserved")

        let disk = JSONConfigurationStorage(directory: root.appendingPathComponent("source-store"))
        let file = try await disk.importAttachment(from: source)
        let config = AppConfiguration(profiles: [profile([Snippet(title: "附件", content: .attachment(file))])])
        let package = root.appendingPathComponent("backup.phraseperch")
        try await disk.export(config, to: package)
        let destination = root.appendingPathComponent("destination")
        let target = JSONConfigurationStorage(directory: destination)
        let original = AppConfiguration(profiles: [profile([Snippet(title: "保留", text: "原配置")])])
        try await target.save(original)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        let prepared = try await target.readImport(package)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path) }
        guard !FileManager.default.isWritableFile(atPath: destination.path) else { throw XCTSkip("Requires a non-root filesystem user") }
        do { try await target.commitImport(prepared); XCTFail("Configuration commit failure expected") } catch {}
        let restored = try await target.load()
        XCTAssertEqual(restored, original)
        let files = try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("attachments").path)
        XCTAssertTrue(files.isEmpty)
        await target.discardImport(prepared)
    }
}
