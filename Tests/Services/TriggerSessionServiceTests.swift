import AppKit
import XCTest
@testable import PhrasePerch

@MainActor
final class TriggerSessionServiceTests: XCTestCase {
    private var repository: ConfigurationRepository!
    private var service: TriggerSessionService!
    private var monitor: StubTriggerSource!
    private var menu: StubFloatingMenu!
    private var worker: StubInputWorker!
    private var paste: StubPasteSystem!
    private var flags: NSEvent.ModifierFlags = []
    private var front: NSRunningApplication?
    private var snippet = Snippet(title: "验收", text: "测试 👩‍💻\n第二行")
    private var attachmentURL: URL?
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() async throws {
        suite = "PhrasePerch.TriggerTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        front = try XCTUnwrap(NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        })
        let storage = StubConfigurationStorage()
        try await storage.save(AppConfiguration(profiles: [AppProfile(
            application: ApplicationIdentity(bundleIdentifier: front?.bundleIdentifier, fallbackBundlePath: nil),
            displayName: "Fixture", displayMode: .both, buttons: [snippet])]))
        let store = ConfigurationRepository(storage: storage)
        repository = store
        for _ in 0..<100 where !store.isReady { try await Task.sleep(for: .milliseconds(5)) }
        let auth = AuthorizationService(store: store, guide: StubAuthorizationGuide(),
            environment: AuthorizationEnvironment(snapshot: { (true, true) }), defaults: defaults)
        monitor = StubTriggerSource()
        menu = StubFloatingMenu()
        worker = StubInputWorker()
        paste = StubPasteSystem()
        var environment = TriggerEnvironment()
        environment.frontmost = { self.front }
        environment.modifiers = { self.flags }
        environment.mouse = { CGPoint(x: 100, y: 100) }
        environment.screens = { [CGRect(x: 0, y: 0, width: 1440, height: 900)] }
        environment.primaryTop = { 900 }
        environment.screenIdentifier = { _ in 42 }
        environment.shortcutKey = { nil }
        service = TriggerSessionService(store: store, input: ContentInsertionService(worker: worker, environment: paste.environment,
            retainAttachment: { _ in
                guard let url = self.attachmentURL else { throw InputFailure("Missing attachment fixture") }
                return url
            }),
            floating: menu, authorization: auth, monitor: monitor, entry: AppEntryService(store: store), environment: environment)
        service.start()
    }
    override func tearDown() async throws {
        service?.stop()
        service = nil
        defaults?.removePersistentDomain(forName: suite)
    }
    private func settle(_ milliseconds: Int = 40) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
    private func modifier(_ flags: NSEvent.ModifierFlags) {
        self.flags = flags
        monitor.onEvent?(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!)
    }
    func testShortcutTapPersistsAndDuplicateClickDispatchesOnce() async throws {
        await worker.setReadback(before: "", selection: NSRange(location: 0, length: 0), readings: [snippet.text])
        monitor.onShortcutDown?()
        monitor.onShortcutDown?()
        monitor.onShortcutUp?()
        try await settle()
        XCTAssertTrue(menu.isPresented)
        XCTAssertEqual(menu.interactionMode, .persistent)
        XCTAssertEqual(menu.shows, 1)
        XCTAssertEqual(service.diagnostics.entries.first?.screenID, 42)
        XCTAssertNotNil(service.diagnostics.entries.first?.readyAfter)
        menu.onSelect?(snippet.id)
        menu.onSelect?(snippet.id)
        try await settle(180)
        XCTAssertEqual(paste.dispatches, 1)
        XCTAssertEqual(paste.copies, [snippet.text])
        XCTAssertFalse(menu.isPresented)
        XCTAssertTrue(menu.messages.allSatisfy(\.isEmpty))
    }
    func testDirectModeRoutesEditableTargetAndBlankCopySeparately() async throws {
        repository.update { $0.preferences.copyOnInsert = false }
        await worker.setCapture(canPaste: true, canDirectWrite: true)
        await worker.setReadback(before: "", selection: NSRange(location: 0, length: 0), readings: [snippet.text])
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        try await settle()
        menu.onSelect?(snippet.id)
        try await settle(180)
        XCTAssertTrue(paste.copies.isEmpty)
        XCTAssertEqual(paste.dispatches, 0)
        let writes = await worker.directWrites
        XCTAssertEqual(writes, [snippet.text])
        await worker.setCapture(canPaste: false, canDirectWrite: false, kind: .nonInput)
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        try await settle()
        XCTAssertTrue(menu.isPresented)
        XCTAssertTrue(menu.messages.allSatisfy(\.isEmpty))
        menu.onSelect?(snippet.id)
        try await settle()
        XCTAssertEqual(paste.copies, [snippet.text])
        XCTAssertEqual(paste.dispatches, 0)
        XCTAssertTrue(menu.messages.allSatisfy(\.isEmpty))
    }
    func testSecondShortcutClosesPersistentMenu() async throws {
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        try await settle()
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        XCTAssertFalse(menu.isPresented)
        XCTAssertEqual(paste.dispatches, 0)
    }
    func testAttachmentSelectionUsesPasteWhenTextDirectWriteIsEnabled() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("test".utf8).write(to: url)
        attachmentURL = url
        repository.update {
            $0.preferences.copyOnInsert = false
            $0.preferences.menuTitleCharacterLimit = 30
            $0.profiles[0].buttons[0].content = .attachment(AttachmentReference(fileName: "test.txt", byteCount: 4))
        }
        await worker.setCapture(canPaste: true, canDirectWrite: false)
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        try await settle()
        XCTAssertEqual(menu.titleCharacterLimit, 30)
        menu.onSelect?(snippet.id); menu.onSelect?(snippet.id)
        try await settle(120)
        XCTAssertEqual(paste.fileCopies, [url])
        XCTAssertEqual(paste.dispatches, 1)
        let writes = await worker.directWrites
        XCTAssertTrue(writes.isEmpty)
    }
    func testQuickOptionReleaseCancelsAndHeldOptionCommits() async throws {
        modifier(.option); modifier([])
        try await settle(150)
        XCTAssertEqual(menu.shows, 0)
        modifier(.option)
        try await settle(160)
        XCTAssertTrue(menu.isPresented)
        menu.selected = snippet.id
        modifier([])
        try await settle()
        XCTAssertEqual(paste.dispatches, 1)
    }
    func testShortcutTakesOverOptionAndIgnoresOptionRelease() async throws {
        modifier(.option)
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        modifier([])
        try await settle(160)
        XCTAssertTrue(menu.isPresented)
        XCTAssertEqual(menu.shows, 1)
        XCTAssertEqual(menu.interactionMode, .persistent)
    }
    func testTimeoutDiscardsLateCaptureAndAllowsRetrigger() async throws {
        await worker.setCapture(delay: .milliseconds(800))
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        try await settle(600)
        XCTAssertFalse(menu.isPresented)
        XCTAssertTrue(menu.messages.contains(where: { $0.contains("超时") }))
        await worker.setCapture()
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        try await settle(80)
        XCTAssertTrue(menu.isPresented)
        XCTAssertEqual(menu.shows, 1)
    }
    func testFocusChangeCancelsPendingCapture() async throws {
        await worker.setCapture(delay: .milliseconds(100))
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        front = nil
        monitor.onFrontChanged?()
        try await settle(160)
        XCTAssertEqual(menu.shows, 0)
        XCTAssertEqual(paste.dispatches, 0)
    }
    func testCopyOnlyDoesNotDispatch() async throws {
        await worker.setCapture(canPaste: false)
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        try await settle()
        menu.onSelect?(snippet.id)
        try await settle()
        XCTAssertEqual(paste.copies, [snippet.text])
        XCTAssertEqual(paste.dispatches, 0)
        XCTAssertTrue(service.notice.isEmpty)
        XCTAssertTrue(menu.messages.allSatisfy(\.isEmpty))
        XCTAssertTrue(service.diagnostics.entries.first?.stage.contains("已复制") == true)
    }
    func testUnknownTargetOpensAndCancelsWithoutPopup() async throws {
        repository.update { $0.preferences.menuAnchorMode = .caret }
        await worker.setCapture(canPaste: false, kind: .unknown)
        monitor.onShortcutDown?(); monitor.onShortcutUp?()
        try await settle()
        XCTAssertTrue(menu.isPresented)
        XCTAssertTrue(menu.messages.allSatisfy(\.isEmpty))
        XCTAssertFalse(service.diagnostics.entries.first?.detail.isEmpty ?? true)
        monitor.onEvent?(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53)!)
        XCTAssertFalse(menu.isPresented)
        XCTAssertTrue(menu.messages.allSatisfy(\.isEmpty))
    }
    func testDiagnosticsKeepOnlyTwentySessions() {
        let diagnostics = InteractionDiagnostics()
        for _ in 0..<25 { diagnostics.record(UUID(), stage: "测试") }
        XCTAssertEqual(diagnostics.entries.count, 20)
    }
}
