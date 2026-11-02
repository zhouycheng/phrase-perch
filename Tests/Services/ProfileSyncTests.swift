import AppKit
import SwiftUI
import XCTest
@testable import PhrasePerch

@MainActor
final class ProfileSyncTests: PresentationTestCase {
    private func profile(_ name: String, buttons: [Snippet] = []) -> AppProfile {
        AppProfile(application: ApplicationIdentity(bundleIdentifier: "sync." + name, fallbackBundlePath: nil),
            displayName: name, displayMode: .both, buttons: buttons)
    }

    private func fixture(_ profiles: [AppProfile]) async throws -> (ConfigurationRepository, ProfileEditingService) {
        let disk = StubConfigurationStorage()
        try await disk.save(AppConfiguration(profiles: profiles))
        let store = ConfigurationRepository(storage: disk)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(store.isReady)
        return (store, ProfileEditingService(repository: store))
    }

    func testNestedSyncPreservesGroupsOrderFlagsAndIndependentOccurrences() async throws {
        let text = Snippet(title: "正文", text: "第一行 👩‍💻\n第二行")
        let file = Snippet(title: "附件", content: .attachment(AttachmentReference(fileName: "a.txt", byteCount: 3)))
        let disabled = Snippet(title: "停用", text: "隐藏", isEnabled: false)
        let group = SnippetGroup(title: "原有分组", children: [MenuNode(kind: .snippet, id: file.id)])
        var source = profile("来源", buttons: [text, file, disabled])
        source.groups = [group]
        source.rootNodes = [MenuNode(kind: .snippet, id: text.id), MenuNode(kind: .group, id: group.id),
            MenuNode(kind: .snippet, id: disabled.id)]
        source.isEnabled = false
        source.displayMode = .shortcutOnly
        let middle = profile("中间"), target = profile("目标")
        let (store, editing) = try await fixture([source, middle, target])
        _ = try editing.addSync(from: source.id, to: middle.id, group: nil)
        _ = try editing.addSync(from: middle.id, to: target.id, group: nil)
        let direct = try editing.addSync(from: source.id, to: target.id, group: nil)
        let resolved = try store.configuration.resolvedProfile(target.id)
        XCTAssertTrue(resolved.canTrigger(.modifier))
        XCTAssertTrue(resolved.canTrigger(.shortcut))
        XCTAssertEqual(RadialNode.contents(profile: resolved, group: nil).map(\.title), ["正文", "原有分组", "正文", "原有分组"])
        XCTAssertEqual(resolved.buttons.count, 6)
        XCTAssertEqual(Set(resolved.buttons.map(\.id)).count, 6)
        XCTAssertFalse(resolved.buttons.contains { $0.id == text.id || $0.id == file.id })
        XCTAssertEqual(resolved.buttons.compactMap(\.attachment), [file.attachment!, file.attachment!])
        for group in resolved.groups {
            XCTAssertEqual(RadialNode.contents(profile: resolved, group: group.id).map(\.title), ["附件"])
        }
        try resolved.validateHierarchy()
        editing.editSync(direct, in: target.id, enabled: false)
        XCTAssertEqual(try store.configuration.resolvedProfile(target.id).enabledNodes().count, 2)
        editing.editProfile(target.id) { $0.isEnabled = false }
        XCTAssertFalse(try store.configuration.resolvedProfile(target.id).canTrigger(.modifier))
    }

    func testSourceChangesPropagateAndEmptySourcesBecomeAvailable() async throws {
        let source = profile("来源"), target = profile("目标")
        let (store, editing) = try await fixture([source, target])
        _ = try editing.addSync(from: source.id, to: target.id, group: nil)
        XCTAssertFalse(try store.configuration.resolvedProfile(target.id).canTrigger(.shortcut))
        let a = try XCTUnwrap(editing.addSnippet(to: source.id))
        let b = try XCTUnwrap(editing.addSnippet(to: source.id))
        editing.editSnippet(profileID: source.id, snippetID: a) { $0.title = "更新标题"; $0.text = "更新正文" }
        editing.reorder(MenuNode(kind: .snippet, id: b), in: source.id, by: -1)
        var result = try store.configuration.resolvedProfile(target.id)
        XCTAssertEqual(result.rootNodes.map { result.title(of: $0) }, ["新文案", "更新标题"])
        XCTAssertEqual(result.buttons.last?.text, "更新正文")
        editing.editSnippet(profileID: source.id, snippetID: b) { $0.isEnabled = false }
        result = try store.configuration.resolvedProfile(target.id)
        XCTAssertEqual(result.enabledNodes().map { result.title(of: $0) }, ["更新标题"])
        _ = editing.removeSnippet(a, in: source.id)
        XCTAssertFalse(try store.configuration.resolvedProfile(target.id).canTrigger(.modifier))
    }

    func testCyclesMissingSourcesAndInvalidDestinationsLeaveConfigurationUntouched() async throws {
        let a = profile("甲"), b = profile("乙"), c = profile("丙")
        let (store, editing) = try await fixture([a, b, c])
        _ = try editing.addSync(from: b.id, to: a.id, group: nil)
        _ = try editing.addSync(from: c.id, to: b.id, group: nil)
        let before = store.configuration, revision = store.revision
        XCTAssertFalse(editing.canSync(a.id, to: c.id))
        for source in [a.id, c.id, UUID()] {
            XCTAssertThrowsError(try editing.addSync(from: source, to: c.id, group: nil))
        }
        XCTAssertThrowsError(try editing.addSync(from: b.id, to: c.id, group: UUID()))
        XCTAssertEqual(store.configuration, before)
        XCTAssertEqual(store.revision, revision)
        var invalid = before
        invalid.profiles[2].syncs = [ProfileSync(sourceProfileID: a.id)]
        invalid.profiles[2].rootNodes = invalid.profiles[2].syncs.map { MenuNode(kind: .sync, id: $0.id) }
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertThrowsError(try invalid.resolvedProfile(a.id))
        invalid.profiles[2].syncs[0].sourceProfileID = UUID()
        XCTAssertThrowsError(try invalid.validate())
    }

    func testBatchCopiesMovesAndDeletesSyncSubtreesAtomically() async throws {
        let source = profile("来源", buttons: [Snippet(title: "保留", text: "正文")])
        var a = profile("甲")
        let group = SnippetGroup(title: "同步容器")
        a.groups = [group]; a.rootNodes = [MenuNode(kind: .group, id: group.id)]
        let b = profile("乙")
        let (store, editing) = try await fixture([source, a, b])
        let syncID = try editing.addSync(from: source.id, to: a.id, group: group.id)
        try editing.transferNodes([group.id], from: a.id, group: nil, to: b.id, group: nil, copying: true)
        let copy = store.configuration.profiles[2]
        XCTAssertNotEqual(copy.syncs[0].id, syncID)
        XCTAssertEqual(copy.syncs[0].sourceProfileID, source.id)
        let before = store.configuration
        XCTAssertThrowsError(try editing.transferNodes([group.id], from: a.id, group: nil,
            to: source.id, group: nil, copying: false))
        XCTAssertEqual(store.configuration, before)
        try editing.transferNodes([syncID], from: a.id, group: group.id, to: b.id, group: nil, copying: false)
        let counts = try editing.deletionCounts([copy.rootNodes[0].id, syncID], in: b.id, group: nil)
        XCTAssertEqual(counts.groups, 1); XCTAssertEqual(counts.syncs, 2); XCTAssertEqual(counts.contents, 0)
        try editing.deleteNodes([copy.rootNodes[0].id, syncID], in: b.id, group: nil)
        XCTAssertTrue(store.configuration.profiles[2].syncs.isEmpty)
        XCTAssertEqual(store.configuration.profiles[0], source)
        try store.configuration.validate()
    }

    func testRemovingSourceCleansAllDirectReferencesInOneUpdate() async throws {
        let a = profile("甲"), b = profile("乙"), c = profile("丙")
        let (store, editing) = try await fixture([a, b, c])
        editing.addGroup(to: b.id, parent: nil)
        let group = try XCTUnwrap(store.configuration.profiles[1].groups.first)
        _ = try editing.addSync(from: a.id, to: b.id, group: group.id)
        _ = try editing.addSync(from: a.id, to: b.id, group: nil)
        _ = try editing.addSync(from: b.id, to: c.id, group: nil)
        _ = try editing.addSync(from: a.id, to: c.id, group: nil)
        let revision = store.revision
        editing.removeProfile(a.id)
        XCTAssertEqual(store.revision, revision + 1)
        XCTAssertTrue(store.configuration.profiles[0].syncs.isEmpty)
        XCTAssertTrue(store.configuration.profiles[0].groups[0].children.isEmpty)
        XCTAssertEqual(store.configuration.profiles[1].syncs.map(\.sourceProfileID), [b.id])
        try store.configuration.validate()
    }

    func testApplicationCopyRetainsSourceAndRemapsSyncAndGroupIDs() async throws {
        let source = profile("来源"), target = profile("目标")
        let (store, editing) = try await fixture([source, target])
        editing.addGroup(to: target.id, parent: nil)
        let groupID = try XCTUnwrap(store.configuration.profiles[1].groups.first?.id)
        let syncID = try editing.addSync(from: source.id, to: target.id, group: groupID)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Copy.app"), contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "sync.copy", "CFBundleName": "复制应用"],
            format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let dialog = StubConfigurationFileDialog()
        dialog.applicationURL = app
        let files = ConfigurationFileService(store: store, editing: editing, dialog: dialog)
        files.duplicateProfile(target.id)
        XCTAssertEqual(store.configuration.profiles.count, 3)
        let copy = try XCTUnwrap(store.configuration.profiles.last)
        XCTAssertNotEqual(copy.id, target.id)
        XCTAssertNotEqual(copy.groups[0].id, groupID)
        XCTAssertNotEqual(copy.syncs[0].id, syncID)
        XCTAssertEqual(copy.syncs[0].sourceProfileID, source.id)
        XCTAssertEqual(copy.groups[0].children, [MenuNode(kind: .sync, id: copy.syncs[0].id)])
        try store.configuration.validate()
    }

    func testSyncInsideOrdinaryGroupUsesExistingPagingAndNestedNavigation() async throws {
        let snippets = (0..<18).map { Snippet(title: "文案 \($0)", text: "正文 \($0)") }
        var source = profile("来源", buttons: snippets), target = profile("目标")
        let sourceGroup = SnippetGroup(title: "来源分组", children: snippets.suffix(5).map { MenuNode(kind: .snippet, id: $0.id) })
        source.groups = [sourceGroup]
        source.rootNodes = snippets.prefix(13).map { MenuNode(kind: .snippet, id: $0.id) } + [MenuNode(kind: .group, id: sourceGroup.id)]
        let container = SnippetGroup(title: "目标分组")
        target.groups = [container]; target.rootNodes = [MenuNode(kind: .group, id: container.id)]
        let (store, editing) = try await fixture([source, target])
        _ = try editing.addSync(from: source.id, to: target.id, group: container.id)
        let resolved = try store.configuration.resolvedProfile(target.id)
        XCTAssertEqual(RadialNode.contents(profile: resolved, group: nil).map(\.title), ["目标分组"])
        var remaining = RadialNode.contents(profile: resolved, group: container.id)
        var titles: [String] = []
        while !remaining.isEmpty {
            let page = try XCTUnwrap(RadialPage(nodes: remaining, anchor: CGPoint(x: 720, y: 450),
                visible: CGRect(x: 0, y: 0, width: 1440, height: 900), hasPrevious: true))
            titles += remaining.prefix(page.consumed).map(\.title)
            remaining = Array(remaining.dropFirst(page.consumed))
        }
        XCTAssertEqual(titles, snippets.prefix(13).map(\.title) + ["来源分组"])
        let nested = try XCTUnwrap(resolved.groups.first { $0.title == "来源分组" })
        XCTAssertEqual(RadialNode.contents(profile: resolved, group: nested.id).map(\.title), snippets.suffix(5).map(\.title))
        editing.editGroup(container.id, in: target.id) { $0.isEnabled = false }
        XCTAssertFalse(try store.configuration.resolvedProfile(target.id).canTrigger(.shortcut))
    }

    func testLegacyConfigurationBackupAndSyncRestartRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = profile("来源"), target = profile("目标")
        let old = AppConfiguration(profiles: [source, target])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        for index in profiles.indices { profiles[index].removeValue(forKey: "syncs") }
        object["profiles"] = profiles
        let disk = JSONConfigurationStorage(directory: directory)
        let restored = try await disk.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored, old)
        try await disk.save(old)
        var updated = old
        let sync = ProfileSync(sourceProfileID: source.id)
        updated.profiles[1].syncs = [sync]
        updated.profiles[1].rootNodes = [MenuNode(kind: .sync, id: sync.id)]
        try await disk.save(updated)
        let loaded = try await disk.load(), backup = try await disk.latestBackup()
        XCTAssertEqual(loaded, updated); XCTAssertEqual(backup, old)
        XCTAssertEqual(loaded.schemaVersion, 2)
    }

    func testAttachmentPackageKeepsSyncReferencesAndSourceResources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("验收.txt")
        try Data("同步附件".utf8).write(to: file)
        let source = profile("来源"), target = profile("目标")
        let disk = JSONConfigurationStorage(directory: directory.appendingPathComponent("original"),
            initialConfiguration: AppConfiguration(profiles: [source, target]))
        let store = ConfigurationRepository(storage: disk)
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let editing = ProfileEditingService(repository: store)
        _ = try await editing.addAttachment(from: file, to: source.id)
        _ = try editing.addSync(from: source.id, to: target.id, group: nil)
        let saved = await store.flush()
        XCTAssertTrue(saved)
        let package = directory.appendingPathComponent("backup.phraseperch")
        try await disk.export(store.configuration, to: package)
        let destination = JSONConfigurationStorage(directory: directory.appendingPathComponent("imported"))
        let prepared = try await destination.readImport(package)
        try await destination.commitImport(prepared)
        let imported = try await destination.load()
        XCTAssertEqual(imported.profiles[1].syncs, store.configuration.profiles[1].syncs)
        let resolved = try imported.resolvedProfile(target.id)
        let attachment = try XCTUnwrap(resolved.buttons.first?.attachment)
        XCTAssertEqual(imported.attachments.count, 1)
        XCTAssertEqual(attachment, imported.attachments.first)
        let url = try await destination.attachmentURL(attachment)
        XCTAssertEqual(try Data(contentsOf: url), Data("同步附件".utf8))
        var broken = imported
        broken.profiles.removeFirst()
        let bad = directory.appendingPathComponent("broken.json")
        try JSONEncoder().encode(broken).write(to: bad)
        do { _ = try await destination.readImport(bad); XCTFail("Missing source must reject import") } catch {}
        let unchanged = try await destination.load()
        XCTAssertEqual(unchanged, imported)
    }

    func testEditorSelectionSourceNavigationAndRenderingAtSupportedSizes() async throws {
        let source = profile("来源应用", buttons: [Snippet(title: "示例", text: "正文")]), target = profile("目标应用")
        let (store, editing) = try await fixture([source, target])
        let coordinator = ApplicationCoordinator(dependencies: AppDependencies(repository: store))
        defer { coordinator.stop() }
        coordinator.mainWindowViewModel.selectProfile(target.id)
        let model = try XCTUnwrap(coordinator.mainWindowViewModel.selectedEditor)
        model.addSync(from: source.id)
        let syncID = try XCTUnwrap(model.selectedSyncID)
        XCTAssertEqual(model.selectedSyncSource?.id, source.id)
        XCTAssertNil(model.selectedSnippet)
        XCTAssertEqual(model.nodeTitle(MenuNode(kind: .sync, id: syncID)), source.displayName)
        for size in [CGSize(width: 880, height: 560), CGSize(width: 960, height: 620),
            CGSize(width: 1070, height: 620), CGSize(width: 1280, height: 800)] {
            let root = NSHostingView(rootView: makeMainWindowView(coordinator))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            try savePreview(root, name: "sync-editor-\(Int(size.width)).png")
            XCTAssertEqual(root.bounds.size, size)
            window.close()
        }
        model.openSyncSource(syncID)
        XCTAssertEqual(coordinator.mainWindowViewModel.selectedProfile, source.id)
        model.duplicateSync(syncID)
        XCTAssertEqual(model.profile?.syncs.count, 2)
        model.removeSync(syncID)
        XCTAssertEqual(model.profile?.syncs.count, 1)
        editing.editProfile(source.id) { $0.displayName = "新名称" }
        XCTAssertEqual(model.selectedSyncSource?.displayName, "新名称")
    }

    func testDesktopSyncAndGroupDoubleClickNavigation() async throws {
        try requireVisibleUITests()
        let source = profile("来源"), target = profile("目标")
        let (store, editing) = try await fixture([source, target])
        let model = ProfileEditorViewModel(profileID: target.id, repository: store, editing: editing)
        defer { model.stop() }
        model.addSync(from: source.id)
        let syncID = try XCTUnwrap(model.selectedSyncID)
        model.openGroup(nil)
        var opened: [UUID] = []
        model.onSelectProfile = { opened.append($0) }
        let root = NSHostingView(rootView: GroupContentsView(viewModel: model)
            .background(EditorStyle.background).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 600, height: 350),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        func click(count: Int, y: CGFloat = 22) throws {
            let point = CGPoint(x: 170, y: root.isFlipped ? y : root.bounds.height - y)
            let now = ProcessInfo.processInfo.systemUptime
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: root.convert(point, to: nil),
                    modifierFlags: [], timestamp: now, windowNumber: window.windowNumber,
                    context: nil, eventNumber: count, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1))
            }
            let down = try event(.leftMouseDown), up = try event(.leftMouseUp)
            NSApp.postEvent(up, atStart: true)
            window.sendEvent(down); window.sendEvent(up)
        }
        try click(count: 1)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.selectedSyncID, syncID)
        XCTAssertTrue(opened.isEmpty)
        try click(count: 2)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(opened, [source.id])
        try savePreview(root, name: "sync-desktop-selection.png")
        model.addGroup()
        let groupID = try XCTUnwrap(model.profile?.groups.first?.id)
        root.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        try click(count: 1, y: 74)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(model.groupPath.isEmpty)
        let fieldEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
        fieldEditor.selectAll(nil)
        fieldEditor.insertText("更新分组名称", replacementRange: fieldEditor.selectedRange())
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.groupTitle(groupID), "更新分组名称")
        try savePreview(root, name: "group-desktop-before-entry.png")
        try click(count: 2, y: 74)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.groupPath, [groupID])
        try savePreview(root, name: "group-desktop-double-click-entry.png")
    }
}
