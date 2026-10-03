import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

final class ConfigurationRepositoryTests: PresentationTestCase {
    @MainActor
    func testEditorAutoSaveStatusFailureRetryAndBackupRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.isReady)
        var profile = AppProfile(
            application: ApplicationIdentity(bundleIdentifier: "test.editor", fallbackBundlePath: nil),
            displayName: "Editor", buttons: [Snippet(title: "第一条", text: "初始正文")])
        store.update { $0.profiles = [profile] }
        XCTAssertEqual(store.saveStatus, "正在保存…")
        var saved = await store.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(store.saveStatus, "已保存")
        profile.buttons[0].text = "修改后的正文"
        store.update { $0.profiles = [profile] }
        for _ in 0..<100 where store.savedRevision != store.revision {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.saveStatus, "已保存")
        let disk = JSONConfigurationStorage(directory: directory)
        let readback = try await disk.load()
        XCTAssertEqual(readback.profiles[0].buttons[0].text, "修改后的正文")
        profile.buttons[0].title = ""
        store.update { $0.profiles = [profile] }
        saved = await store.flush()
        XCTAssertFalse(saved)
        XCTAssertEqual(store.saveStatus, "待补全")
        XCTAssertNil(store.issue)
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].text, "修改后的正文")
        profile.buttons[0].title = "修复标题"
        store.update { $0.profiles = [profile] }
        saved = await store.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(store.saveStatus, "已保存")
        await store.restoreBackup()
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].title, "第一条")
        XCTAssertEqual(store.saveStatus, "已保存")
    }

    @MainActor
    func testConfigurationIssuesAndDraftHintsRenderWithoutTopBanner() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        store.update {
            $0.profiles = [
                AppProfile(
                    application: ApplicationIdentity(bundleIdentifier: "preview.validation", fallbackBundlePath: nil),
                    displayName: "编辑示例", buttons: [Snippet(title: "", text: "")])
            ]
        }
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        defer { coordinator.stop() }
        for operation in [ConfigurationIssue.Operation.save, .load, .importFile, .exportFile, .recovery] {
            let isolated = ConfigurationRepository(directory: directory.appendingPathComponent(operation.rawValue))
            for _ in 0..<100 where !isolated.isReady { try await Task.sleep(for: .milliseconds(10)) }
            isolated.update { $0 = store.configuration }
            isolated.report(operation, message: "测试文件操作详情：请检查配置并重试。")
            let issueCoordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: isolated))
            for size in [
                CGSize(width: 880, height: 560), CGSize(width: 960, height: 620),
                CGSize(width: 1280, height: 800),
            ] {
                for page in [MainPage.home, .settings] {
                    let root = NSHostingView(rootView: makeMainWindowView(issueCoordinator, page: page))
                    let window = NSWindow(
                        contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                        backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: .darkAqua)
                    window.contentView = root
                    root.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(50))
                    try savePreview(root, name: "issue-\(operation)-\(page)-\(Int(size.width)).png")
                    if page == .settings {
                        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                        let scroll = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }.first)
                        let document = try XCTUnwrap(scroll.documentView)
                        document.scroll(
                            NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                        try await Task.sleep(for: .milliseconds(50))
                        try savePreview(root, name: "issue-\(operation)-configuration-\(Int(size.width)).png")
                    }
                    XCTAssertEqual(root.bounds.size, size)
                    window.close()
                }
            }
            issueCoordinator.stop()
        }
        let unavailable = directory.appendingPathComponent("unavailable")
        try FileManager.default.createDirectory(at: unavailable, withIntermediateDirectories: true)
        try Data("damaged".utf8).write(to: unavailable.appendingPathComponent("configuration.json"))
        let failedStore = ConfigurationRepository(directory: unavailable)
        for _ in 0..<100 where failedStore.issue == nil { try await Task.sleep(for: .milliseconds(10)) }
        let failedCoordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: failedStore))
        defer { failedCoordinator.stop() }
        let root = NSHostingView(rootView: makeMainWindowView(failedCoordinator))
        root.frame = CGRect(x: 0, y: 0, width: 960, height: 620)
        root.appearance = NSAppearance(named: .darkAqua)
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        try savePreview(root, name: "issue-load-unavailable.png")
    }

    @MainActor
    func testIncompleteDraftKeepsDiskContentsAndResumesAutoSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        store.update {
            $0.profiles = [
                AppProfile(
                    application: ApplicationIdentity(bundleIdentifier: "test.draft", fallbackBundlePath: nil),
                    displayName: "Draft", buttons: [Snippet(title: "标题", text: "原正文")])
            ]
        }
        let initiallySaved = await store.flush()
        XCTAssertTrue(initiallySaved)
        let file = directory.appendingPathComponent("configuration.json")
        let original = try Data(contentsOf: file)
        for invalid in [
            Snippet(title: "", text: "新正文"), Snippet(title: "标题", text: ""),
            Snippet(title: "标题", text: String(repeating: "中", count: 22000)),
            Snippet(title: "标题", text: "bad\u{0}"),
        ] {
            store.update { $0.profiles[0].buttons[0].title = invalid.title }
            store.update { $0.profiles[0].buttons[0].text = invalid.text }
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(store.saveStatus, "待补全")
            XCTAssertNil(store.issue)
            XCTAssertEqual(try Data(contentsOf: file), original)
            let saved = await store.flush()
            XCTAssertFalse(saved)
            XCTAssertNil(store.issue)
        }
        store.update { $0.profiles[0].buttons[0].title = "补齐标题" }
        store.update { $0.profiles[0].buttons[0].text = "新的完整正文" }
        for _ in 0..<100 where store.savedRevision != store.revision {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.saveStatus, "已保存")
        let disk = JSONConfigurationStorage(directory: directory)
        let persisted = try await disk.load()
        XCTAssertEqual(persisted.profiles[0].buttons[0].text, "新的完整正文")
    }

    @MainActor
    func testDiskSaveFailureKeepsDraftAndCanRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        try Data("block directory".utf8).write(to: directory)
        store.update {
            $0.profiles = [
                AppProfile(
                    application: ApplicationIdentity(bundleIdentifier: "test.disk", fallbackBundlePath: nil),
                    displayName: "Disk", buttons: [Snippet(title: "标题", text: "内存草稿")])
            ]
        }
        let failed = await store.flush()
        XCTAssertFalse(failed)
        XCTAssertEqual(store.issue?.operation, .save)
        XCTAssertEqual(store.saveStatus, "保存失败")
        XCTAssertEqual(store.configuration.profiles[0].buttons[0].text, "内存草稿")
        store.report(.exportFile, message: "导出目标不可用")
        XCTAssertEqual(store.saveStatus, "保存失败")
        XCTAssertEqual(store.issue?.operation, .save)
        try FileManager.default.removeItem(at: directory)
        let retried = await store.flush()
        XCTAssertTrue(retried)
        XCTAssertNil(store.saveIssue)
        XCTAssertEqual(store.issue?.operation, .exportFile)
        XCTAssertEqual(store.saveStatus, "已保存")
    }

    @MainActor
    func testFailedLoadCannotOverwriteOriginalAndCanRetryOrRecoverBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("configuration.json")
        let damaged = Data("damaged configuration".utf8)
        try damaged.write(to: file)
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where store.issue == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isReady)
        XCTAssertEqual(store.issue?.operation, .load)
        XCTAssertEqual(store.saveStatus, "读取失败")
        let flushed = await store.flush()
        XCTAssertFalse(flushed)
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        let valid = try JSONEncoder().encode(AppConfiguration())
        try valid.write(to: file)
        await store.retryLoad()
        XCTAssertTrue(store.isReady)
        XCTAssertNil(store.issue)

        try damaged.write(to: file)
        try valid.write(to: directory.appendingPathComponent("backup-test.json"))
        let recoveryStore = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where recoveryStore.issue == nil { try await Task.sleep(for: .milliseconds(10)) }
        await recoveryStore.restoreBackup()
        XCTAssertTrue(recoveryStore.isReady)
        XCTAssertNil(recoveryStore.issue)
        XCTAssertEqual(recoveryStore.saveStatus, "已保存")
        let disk = JSONConfigurationStorage(directory: directory)
        let recovered = try await disk.load()
        XCTAssertEqual(recovered.schemaVersion, 2)
        let retained = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("damaged-") }
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(try Data(contentsOf: retained[0]), damaged)
    }

    @MainActor
    func testImportAndExportFailuresDoNotMisreportPersistenceStatus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let saved = await store.flush()
        XCTAssertTrue(saved)
        await store.replace(with: AppConfiguration(schemaVersion: 999))
        XCTAssertEqual(store.issue?.operation, .importFile)
        XCTAssertEqual(store.configuration.schemaVersion, 2)
        XCTAssertEqual(store.saveStatus, "已保存")
        await store.export(to: directory.appendingPathComponent("missing/export.json"))
        XCTAssertEqual(store.issue?.operation, .exportFile)
        XCTAssertEqual(store.saveStatus, "已保存")
        await store.export(to: directory.appendingPathComponent("export.json"))
        XCTAssertNil(store.issue)
    }

    func testAtomicStorageAndCorruptRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = JSONConfigurationStorage(directory: directory)
        var config = AppConfiguration()
        try await disk.save(config)
        for _ in 0..<5 {
            config.preferences.isEnabled.toggle()
            try await disk.save(config)
        }
        let loaded = try await disk.load()
        XCTAssertEqual(loaded, config)
        let backups = try await disk.backups()
        XCTAssertEqual(backups.count, 3)
        let file = directory.appendingPathComponent("configuration.json")
        try Data("broken".utf8).write(to: file)
        do {
            _ = try await disk.load()
            XCTFail("Corrupt configuration must not be silently reset")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8))
        let recovered = try await disk.latestBackup()
        try await disk.save(recovered)
        let reloaded = try await disk.load()
        XCTAssertEqual(reloaded, recovered)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix("damaged-") })
    }

    func testInvalidSaveLeavesOldFileUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = JSONConfigurationStorage(directory: directory)
        try await disk.save(AppConfiguration())
        let file = directory.appendingPathComponent("configuration.json")
        let before = try Data(contentsOf: file)
        do {
            try await disk.save(AppConfiguration(schemaVersion: 999))
            XCTFail("Future version must be rejected")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: file), before)
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let blockedDisk = JSONConfigurationStorage(directory: blocked)
        do {
            try await blockedDisk.save(AppConfiguration())
            XCTFail("Disk error must propagate")
        } catch {}
    }
}
