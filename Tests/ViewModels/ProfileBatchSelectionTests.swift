import XCTest
@testable import PhrasePerch

@MainActor
final class ProfileBatchSelectionTests: XCTestCase {
    private func fixture() async throws -> (ConfigurationRepository, ProfileEditorViewModel, AppProfile) {
        let store = ConfigurationRepository(storage: StubConfigurationStorage())
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let snippets = (0..<4).map { Snippet(title: "文案\($0)", text: "正文\($0)") }
        let child = SnippetGroup(title: "子分组")
        let parent = SnippetGroup(title: "父分组", children: [MenuNode(kind: .group, id: child.id)])
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "selection.source", fallbackBundlePath: nil),
            displayName: "来源", buttons: snippets, groups: [parent, child],
            rootNodes: snippets.map { MenuNode(kind: .snippet, id: $0.id) } + [MenuNode(kind: .group, id: parent.id)])
        store.update { $0.profiles = [profile] }
        return (store, ProfileEditorViewModel(profileID: profile.id, repository: store,
            editing: ProfileEditingService(repository: store)), profile)
    }

    func testSelectionIsIndependentFromEditorAndNavigationClearsIt() async throws {
        let (_, model, profile) = try await fixture()
        defer { model.stop() }
        model.select(profile.buttons[1].id)
        model.toggleNodeSelection(profile.buttons[0].id)
        model.activateNode(profile.rootNodes[2])
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[0].id, profile.buttons[2].id])
        XCTAssertEqual(model.session.selectedID, profile.buttons[1].id)
        model.activateNode(profile.rootNodes[0])
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[2].id])
        model.openGroup(profile.groups[0].id)
        XCTAssertTrue(model.selectedNodeIDs.isEmpty)
        model.toggleNodeSelection(profile.groups[1].id)
        model.openGroup(nil)
        XCTAssertTrue(model.selectedNodeIDs.isEmpty)
        model.toggleNodeSelection(UUID())
        XCTAssertFalse(model.isBatchSelecting)
    }

    func testMarqueeReplacesOrAddsAndCancellationRestoresOriginalSelection() async throws {
        let (_, model, profile) = try await fixture()
        defer { model.stop() }
        let frames = Dictionary(uniqueKeysWithValues: profile.rootNodes.enumerated().map {
            ($0.element.id, CGRect(x: 0, y: $0.offset * 52, width: 300, height: 44))
        })
        model.toggleNodeSelection(profile.buttons[3].id)
        model.beginMarquee(at: CGPoint(x: 20, y: 49), additive: false)
        model.updateMarquee(to: CGPoint(x: 200, y: 120), frames: frames, additive: false)
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[1].id, profile.buttons[2].id])
        model.finishListGesture(inside: true)
        XCTAssertNil(model.marqueeRect)
        model.beginMarquee(at: CGPoint(x: 20, y: 49), additive: true)
        model.updateMarquee(to: CGPoint(x: 200, y: 0), frames: frames, additive: true)
        XCTAssertEqual(model.selectedNodeIDs, Set(profile.buttons.prefix(3).map(\.id)))
        model.finishListGesture(inside: false)
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[1].id, profile.buttons[2].id])
        model.clearBatchSelection()
        XCTAssertTrue(model.selectedNodeIDs.isEmpty)
    }

    func testDraggingSelectionPreservesOrderAndCommitsOnlyOnDrop() async throws {
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        model.select(profile.buttons[1].id)
        model.toggleNodeSelection(profile.buttons[0].id)
        model.toggleNodeSelection(profile.buttons[2].id)
        let frames = Dictionary(uniqueKeysWithValues: profile.rootNodes.enumerated().map {
            ($0.element.id, CGRect(x: 0, y: $0.offset * 52, width: 300, height: 44))
        })
        let revision = store.revision
        model.beginReordering(profile.buttons[2].id)
        model.updateInsertion(at: CGPoint(x: 30, y: 250), frames: frames)
        XCTAssertEqual(store.revision, revision)
        model.finishListGesture(inside: false)
        XCTAssertEqual(model.nodes, profile.rootNodes)
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[0].id, profile.buttons[2].id])
        model.beginReordering(profile.buttons[2].id)
        model.updateInsertion(at: CGPoint(x: 30, y: 250), frames: frames)
        model.finishListGesture(inside: true)
        XCTAssertEqual(model.nodes.map(\.id), [profile.buttons[1].id, profile.buttons[3].id, profile.groups[0].id,
            profile.buttons[0].id, profile.buttons[2].id])
        XCTAssertEqual(store.revision, revision + 1)
        XCTAssertEqual(model.session.selectedID, profile.buttons[1].id)
        model.beginReordering(profile.buttons[3].id)
        XCTAssertEqual(model.draggingNodeIDs, [profile.buttons[3].id])
        model.cancelListGesture()
        XCTAssertEqual(model.selectedNodeIDs, [profile.buttons[0].id, profile.buttons[2].id])
    }

    func testCopyRetainsSelectionAndDeleteCancellationKeepsEditor() async throws {
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        model.select(profile.buttons[2].id)
        model.toggleNodeSelection(profile.buttons[0].id)
        model.toggleNodeSelection(profile.buttons[1].id)
        model.transferSelection(to: profile.id, group: nil, copying: true)
        XCTAssertEqual(model.nodes.count, profile.rootNodes.count + 2)
        XCTAssertEqual(model.selectedNodeIDs, Set(profile.buttons.prefix(2).map(\.id)))
        let before = store.configuration
        model.requestBatchDeletion()
        XCTAssertTrue(model.batchDeletionMessage.contains("2 条内容"))
        model.cancelBatchDeletion()
        XCTAssertEqual(store.configuration, before)
        XCTAssertEqual(model.session.selectedID, profile.buttons[2].id)
        model.requestBatchDeletion()
        model.confirmBatchDeletion()
        XCTAssertTrue(model.selectedNodeIDs.isEmpty)
        XCTAssertEqual(model.session.selectedID, profile.buttons[2].id)
        XCTAssertFalse(model.ids.contains(profile.buttons[0].id))
    }

    func testInvalidDestinationReportsFailureAndExternalChangesCancelDrag() async throws {
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        model.toggleNodeSelection(profile.groups[0].id)
        XCTAssertFalse(model.canTransferSelection(to: profile, group: nil, copying: false))
        XCTAssertFalse(model.canTransferSelection(to: profile, group: profile.groups[1].id, copying: false))
        XCTAssertTrue(model.canTransferSelection(to: profile, group: profile.groups[1].id, copying: true))
        model.transferSelection(to: UUID(), group: nil, copying: false)
        XCTAssertNotNil(model.batchIssue)
        XCTAssertEqual(model.selectedNodeIDs, [profile.groups[0].id])
        model.beginReordering(profile.groups[0].id)
        ProfileEditingService(repository: store).removeGroup(profile.groups[0].id, in: profile.id)
        XCTAssertFalse(model.isListGestureActive)
        XCTAssertTrue(model.selectedNodeIDs.isEmpty)
    }

    func testSwitchingApplicationsClearsBatchButKeepsEditorSession() async throws {
        let (store, editor, profile) = try await fixture()
        editor.stop()
        let target = AppProfile(application: ApplicationIdentity(bundleIdentifier: "selection.target", fallbackBundlePath: nil), displayName: "目标")
        store.update { $0.profiles.append(target) }
        let editing = ProfileEditingService(repository: store)
        let model = MainWindowViewModel(repository: store, editing: editing,
            files: ConfigurationFileService(store: store, editing: editing, dialog: StubConfigurationFileDialog()),
            authorization: AuthorizationService(store: store, guide: StubAuthorizationGuide()))
        defer { model.stop() }
        model.selectedEditor?.select(profile.buttons[2].id)
        model.selectedEditor?.toggleNodeSelection(profile.buttons[0].id)
        model.selectProfile(target.id)
        model.selectProfile(profile.id)
        XCTAssertTrue(model.selectedEditor?.selectedNodeIDs.isEmpty == true)
        XCTAssertEqual(model.selectedEditor?.session.selectedID, profile.buttons[2].id)
    }

    func testChangedSubtreeRequiresDeletionToBeConfirmedAgain() async throws {
        let (store, model, profile) = try await fixture()
        defer { model.stop() }
        model.toggleNodeSelection(profile.groups[0].id)
        model.requestBatchDeletion()
        _ = ProfileEditingService(repository: store).addSnippet(to: profile.id, group: profile.groups[1].id)
        let before = store.configuration
        model.confirmBatchDeletion()
        XCTAssertEqual(store.configuration, before)
        XCTAssertNotNil(model.batchIssue)
        XCTAssertEqual(model.selectedNodeIDs, [profile.groups[0].id])
    }
}
