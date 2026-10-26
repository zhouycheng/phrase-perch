import XCTest
@testable import PhrasePerch

@MainActor
final class ProfileBatchEditingTests: XCTestCase {
    private func fixture() async throws -> (ConfigurationRepository, ProfileEditingService, AppProfile, AppProfile, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationRepository(directory: directory.appendingPathComponent("configuration"))
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.isReady)
        let a = Snippet(title: "甲", text: "正文甲"), b = Snippet(title: "乙", text: "正文乙", isEnabled: false)
        let nested = Snippet(title: "嵌套文案", text: "正文 👩‍💻\n第二行")
        let child = SnippetGroup(title: "子分组", children: [MenuNode(kind: .snippet, id: nested.id)])
        let parent = SnippetGroup(title: "父分组", children: [MenuNode(kind: .group, id: child.id)])
        let destination = SnippetGroup(title: "目标分组")
        let source = AppProfile(application: ApplicationIdentity(bundleIdentifier: "batch.source", fallbackBundlePath: nil),
            displayName: "来源", buttons: [a, b, nested], groups: [parent, child, destination],
            rootNodes: [MenuNode(kind: .snippet, id: a.id), MenuNode(kind: .group, id: parent.id),
                MenuNode(kind: .snippet, id: b.id), MenuNode(kind: .group, id: destination.id)])
        let target = AppProfile(application: ApplicationIdentity(bundleIdentifier: "batch.target", fallbackBundlePath: nil),
            displayName: "停用的目标", isEnabled: false, buttons: [Snippet(title: "原有内容", text: "保留")])
        store.update { $0.profiles = [source, target] }
        return (store, ProfileEditingService(repository: store), source, target, directory)
    }

    func testCrossApplicationMoveCommitsOnceAndPersistsCompleteSubtrees() async throws {
        let (store, editing, source, target, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selected: Set<UUID> = [source.rootNodes[1].id, source.rootNodes[2].id]
        let revision = store.revision
        var notifications = 0
        let token = store.observe { notifications += 1 }
        defer { store.removeObserver(token) }
        try editing.transferNodes(selected, from: source.id, group: nil, to: target.id, group: nil, copying: false)
        XCTAssertEqual(store.revision, revision + 1)
        XCTAssertEqual(notifications, 1)
        let result = store.configuration.profiles
        XCTAssertEqual(result[0].rootNodes, [source.rootNodes[0], source.rootNodes[3]])
        XCTAssertEqual(result[1].rootNodes, target.rootNodes + [source.rootNodes[1], source.rootNodes[2]])
        XCTAssertEqual(result[1].groups, Array(source.groups.prefix(2)))
        XCTAssertEqual(result[1].buttons.first { $0.id == source.buttons[1].id }, source.buttons[1])
        XCTAssertFalse(result[1].isEnabled)
        try store.configuration.validate()
        let saved = await store.flush()
        XCTAssertTrue(saved)
        let readback = try await JSONConfigurationStorage(directory: directory.appendingPathComponent("configuration")).load()
        XCTAssertEqual(readback, store.configuration)
    }

    func testSameApplicationMovePreservesObjectsAndAppendsInSourceOrder() async throws {
        let (store, editing, source, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try editing.transferNodes([source.buttons[1].id, source.buttons[0].id], from: source.id, group: nil,
            to: source.id, group: source.groups[2].id, copying: false)
        let result = store.configuration.profiles[0]
        XCTAssertEqual(result.buttons, source.buttons)
        XCTAssertEqual(result.children(of: source.groups[2].id).map(\.id), Array(source.buttons.prefix(2)).map(\.id))
        XCTAssertEqual(result.rootNodes, [source.rootNodes[1], source.rootNodes[3]])
        try result.validateHierarchy()
    }

    func testCopyIntoOwnDescendantUsesSnapshotAndFreshNodeIDs() async throws {
        let (store, editing, source, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try editing.transferNodes([source.groups[0].id], from: source.id, group: nil,
            to: source.id, group: source.groups[1].id, copying: true)
        let result = store.configuration.profiles[0]
        XCTAssertEqual(result.rootNodes, source.rootNodes)
        XCTAssertEqual(result.groups.count, source.groups.count + 2)
        XCTAssertEqual(result.buttons.count, source.buttons.count + 1)
        let copiedParent = try XCTUnwrap(result.groups.first { $0.id == result.groups[1].children.last?.id })
        XCTAssertEqual(copiedParent.title, source.groups[0].title)
        XCTAssertFalse(source.groups.contains { $0.id == copiedParent.id })
        let copiedChild = try XCTUnwrap(result.groups.first { $0.id == copiedParent.children.first?.id })
        let copiedText = try XCTUnwrap(result.buttons.first { $0.id == copiedChild.children.first?.id })
        XCTAssertEqual(copiedText.content, source.buttons[2].content)
        XCTAssertNotEqual(copiedText.id, source.buttons[2].id)
        try store.configuration.validate()
    }

    func testRecursiveDeletionCountsAndRemovesOnlySelectedSubtrees() async throws {
        let (store, editing, source, target, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selection: Set<UUID> = [source.groups[0].id, source.buttons[0].id]
        let counts = try editing.deletionCounts(selection, in: source.id, group: nil)
        XCTAssertEqual(counts.groups, 2)
        XCTAssertEqual(counts.contents, 2)
        try editing.deleteNodes(selection, in: source.id, group: nil)
        XCTAssertEqual(store.configuration.profiles[0].rootNodes, Array(source.rootNodes.suffix(2)))
        XCTAssertEqual(store.configuration.profiles[0].buttons, [source.buttons[1]])
        XCTAssertEqual(store.configuration.profiles[0].groups, [source.groups[2]])
        XCTAssertEqual(store.configuration.profiles[1], target)
        try store.configuration.validate()
    }

    func testInvalidMovesAndStaleSelectionsLeaveConfigurationUntouched() async throws {
        let (store, editing, source, target, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = store.configuration, revision = store.revision
        for group in [nil, source.groups[0].id, source.groups[1].id, UUID()] {
            XCTAssertThrowsError(try editing.transferNodes([source.groups[0].id], from: source.id, group: nil,
                to: source.id, group: group, copying: false))
            XCTAssertEqual(store.configuration, before)
        }
        XCTAssertThrowsError(try editing.transferNodes([source.buttons[0].id, UUID()], from: source.id, group: nil,
            to: target.id, group: nil, copying: false))
        XCTAssertThrowsError(try editing.deleteNodes([source.groups[1].id], in: source.id, group: nil))
        XCTAssertThrowsError(try editing.reorderNodes([source.buttons[0].id], in: source.id, group: nil, before: UUID()))
        XCTAssertEqual(store.configuration, before)
        XCTAssertEqual(store.revision, revision)
    }

    func testBlockReorderUpdatesRuntimeOrderAndKeepsDisabledContent() async throws {
        let (store, editing, source, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try editing.reorderNodes([source.buttons[1].id, source.buttons[0].id], in: source.id,
            group: nil, before: source.groups[2].id)
        let result = store.configuration.profiles[0]
        XCTAssertEqual(result.rootNodes, [source.rootNodes[1], source.rootNodes[0], source.rootNodes[2], source.rootNodes[3]])
        XCTAssertEqual(result.buttons, source.buttons)
        let runtimeIDs = RadialNode.contents(profile: result, group: nil).compactMap { node -> UUID? in
            switch node.action { case .content(let id), .group(let id): return id; default: return nil }
        }
        XCTAssertEqual(runtimeIDs, [source.groups[0].id, source.buttons[0].id])
        let saved = await store.flush()
        XCTAssertTrue(saved)
        let readback = try await JSONConfigurationStorage(directory: directory.appendingPathComponent("configuration")).load()
        XCTAssertEqual(readback.profiles[0].rootNodes, result.rootNodes)
    }

    func testCopiedAttachmentSurvivesDeletingOriginalAndCleanup() async throws {
        let (store, editing, source, target, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("示例.txt")
        try Data("附件内容".utf8).write(to: input)
        let originalID = try await editing.addAttachment(from: input, to: source.id)
        let asset = try XCTUnwrap(store.configuration.profiles[0].buttons.first { $0.id == originalID }?.attachment)
        try editing.transferNodes([originalID], from: source.id, group: nil, to: target.id, group: nil, copying: true)
        let copy = try XCTUnwrap(store.configuration.profiles[1].buttons.last)
        XCTAssertNotEqual(copy.id, originalID)
        XCTAssertEqual(copy.attachment, asset)
        try editing.deleteNodes([originalID], in: source.id, group: nil)
        let saved = await store.flush()
        XCTAssertTrue(saved)
        await store.cleanupAttachments()
        let url = try await store.attachmentURL(asset)
        XCTAssertEqual(try Data(contentsOf: url), Data("附件内容".utf8))
    }

    func testReorderedContentKeepsItsOrderAcrossRuntimePages() async throws {
        let (store, editing, source, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snippets = (0..<20).map { Snippet(title: "文案\($0)", text: "正文") }
        var profile = source
        profile.buttons = snippets
        profile.groups = []
        profile.rootNodes = snippets.map { MenuNode(kind: .snippet, id: $0.id) }
        store.update { $0.profiles = [profile] }
        try editing.reorderNodes([snippets[2].id, snippets[5].id, snippets[12].id],
            in: profile.id, group: nil, before: snippets[19].id)
        let result = store.configuration.profiles[0]
        var remaining = RadialNode.contents(profile: result, group: nil), visited: [UUID] = []
        var previous = false
        while !remaining.isEmpty {
            let page = try XCTUnwrap(RadialPage(nodes: remaining, anchor: CGPoint(x: 1000, y: 800),
                visible: CGRect(x: 0, y: 0, width: 2400, height: 1800), hasPrevious: previous))
            visited += page.slots.compactMap { $0?.contentID }
            remaining.removeFirst(page.consumed)
            previous = true
        }
        XCTAssertEqual(visited, result.enabledNodes().map(\.id))
    }
}
