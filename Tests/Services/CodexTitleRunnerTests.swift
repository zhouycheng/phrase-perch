import Darwin
import XCTest

@testable import PhrasePerch

final class CodexTitleRunnerTests: XCTestCase {
    @MainActor
    func testLiveCodexGenerationPersistsAndRestoresInBuiltApplication() async throws {
        guard ProcessInfo.processInfo.environment["PHRASEPERCH_LIVE_TITLE_TESTS"] == "1" else {
            throw XCTSkip("Live generation requires PHRASEPERCH_LIVE_TITLE_TESTS=1")
        }
        var runner = CodexTitleRunner()
        runner.environment.removeValue(forKey: "PATH")
        let status = try await runner.check(at: "")
        XCTAssertTrue(status.contains("已就绪"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !repository.isReady { try await Task.sleep(for: .milliseconds(10)) }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test.live.codex", fallbackBundlePath: nil),
            displayName: "Test", buttons: [Snippet(title: "原标题", text: "请解释这段代码的实现过程并给出修改建议。")])
        repository.update { $0.profiles = [profile]; $0.preferences.titleGenerationProvider = .codexCLI }
        let dependencies = AppDependencies(repository: repository, titleService: TitleGenerationService(codex: runner))
        defer { dependencies.mainWindowViewModel.stop() }
        let editor = try XCTUnwrap(dependencies.mainWindowViewModel.selectedEditor)
        editor.generateTitle()
        for _ in 0..<700 where editor.isGeneratingTitle { try await Task.sleep(for: .milliseconds(100)) }
        if let message = editor.titleGenerationMessage { throw InputFailure(message) }
        XCTAssertFalse(editor.isGeneratingTitle)
        let title = try XCTUnwrap(editor.selectedSnippet?.title)
        XCTAssertNotEqual(title, "原标题")
        XCTAssertEqual(try TitleGenerationService.cleanTitle(title), title)
        let saved = await repository.flush()
        XCTAssertTrue(saved)
        let reopened = ConfigurationRepository(directory: directory)
        for _ in 0..<100 where !reopened.isReady { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reopened.configuration.preferences.titleGenerationProvider, .codexCLI)
        XCTAssertEqual(reopened.configuration.profiles[0].buttons[0].title, title)
        editor.generateTitle()
        try await Task.sleep(for: .milliseconds(100))
        dependencies.mainWindow.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(editor.isGeneratingTitle)
        XCTAssertEqual(editor.selectedSnippet?.title, title)
        print("Live Codex title: \(title)")
    }

    func testLiveCLIProxyAPIGeneration() async throws {
        guard ProcessInfo.processInfo.environment["PHRASEPERCH_LIVE_TITLE_TESTS"] == "1" else {
            throw XCTSkip("Live generation requires PHRASEPERCH_LIVE_TITLE_TESTS=1")
        }
        let service = TitleGenerationService()
        let models: [String]
        do { models = try await service.models(at: Preferences.defaultTitleAPIBaseURL) }
        catch { throw XCTSkip("Local CLIProxyAPI unavailable: \(error.localizedDescription)") }
        var preferences = Preferences()
        preferences.titleModel = try XCTUnwrap(models.first)
        let title = try await service.generateTitle(for: "请解释这段代码的实现过程。", preferences: preferences)
        XCTAssertEqual(try TitleGenerationService.cleanTitle(title), title)
        print("Live CLIProxyAPI title: \(title)")
    }

    func testEnvironmentDetectionAndExplicitInvalidPath() async throws {
        let stub = try StubCodexCLI()
        defer { stub.cleanup() }
        var runner = stub.runner
        runner.environment["PATH"] = stub.executable.deletingLastPathComponent().path
        XCTAssertEqual(try runner.executable(at: ""), stub.executable)
        XCTAssertThrowsError(try runner.executable(at: "/missing/codex"))
        XCTAssertThrowsError(try runner.executable(at: stub.directory.path))
        let message = try await runner.check(at: stub.executable.path)
        XCTAssertTrue(message.contains("已就绪"))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: stub.directory.path).contains { $0.hasPrefix("PhrasePerch-Codex-") })
    }

    func testGenerationUsesStdinDefaultModelAndDisablesExtraCapabilities() async throws {
        let stub = try StubCodexCLI(generation: "awk 'BEGIN { for (i=0; i<30000; i++) print \"diagnostic\" }' >&2; printf '“代码解释”\\n'")
        defer { stub.cleanup() }
        var preferences = Preferences()
        preferences.titleGenerationProvider = .codexCLI
        preferences.codexExecutablePath = stub.executable.path
        let text = "正文含 '引号'、\"双引号\"、$(echo danger)、`echo danger`\n以及 Emoji 👩‍💻"
        let service = TitleGenerationService(codex: stub.runner)
        let title = try await service.generateTitle(for: text, preferences: preferences)
        XCTAssertEqual(title, "代码解释")
        XCTAssertEqual(try stub.read("stdin"), text)
        let args = try stub.read("arguments").split(separator: "\n").map(String.init)
        XCTAssertTrue(args.contains("--no-daemon"))
        XCTAssertTrue(args.contains("never"))
        XCTAssertTrue(args.contains("read-only"))
        XCTAssertTrue(args.contains("--ephemeral"))
        XCTAssertTrue(args.contains("web_search=\"disabled\""))
        XCTAssertTrue(args.contains("project_doc_max_bytes=0"))
        XCTAssertTrue(args.contains("mcp_servers={\"test.server\"={enabled=false}}"))
        for feature in ["shell_tool", "apps", "plugins", "hooks", "browser_use", "computer_use", "memories", "multi_agent"] {
            XCTAssertTrue(args.contains(feature), feature)
        }
        XCTAssertFalse(args.contains("--model"))
        XCTAssertFalse(args.contains(text))
        let cwd = try stub.read("cwd").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(cwd.contains("PhrasePerch-Codex-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwd))
    }

    func testMCPFailureLoginAndVersionErrorsPreventGeneration() async throws {
        for (mcp, login, help, expected) in [
            ("printf 'invalid'", "printf 'Logged in'", "printf '%s' --ephemeral", "MCP"),
            ("printf '[]'", "printf 'Not logged in' >&2; exit 1", "printf '%s\\n' --skip-git-repo-check --ephemeral --sandbox --color --config --disable", "登录"),
            ("printf '[]'", "printf 'Logged in'", "printf 'old version'", "不兼容"),
        ] {
            let stub = try StubCodexCLI(mcp: mcp, login: login, help: help)
            defer { stub.cleanup() }
            do {
                if expected == "MCP" {
                    _ = try await stub.runner.generate(for: "正文", path: stub.executable.path, instructions: TitleGenerationService.titleInstructions)
                } else {
                    _ = try await stub.runner.check(at: stub.executable.path)
                }
                XCTFail("Expected error")
            } catch { XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: stub.directory.appendingPathComponent("stdin").path))
        }
    }

    func testInvalidOutputAndFailedProcessKeepControlledErrors() async throws {
        for generation in ["printf '标题\\n解释'", "exit 3", "printf '401 unauthorized' >&2; exit 1"] {
            let stub = try StubCodexCLI(generation: generation)
            defer { stub.cleanup() }
            var preferences = Preferences()
            preferences.titleGenerationProvider = .codexCLI
            preferences.codexExecutablePath = stub.executable.path
            do {
                _ = try await TitleGenerationService(codex: stub.runner).generateTitle(for: "正文", preferences: preferences)
                XCTFail("Expected error")
            } catch { XCTAssertTrue(error is InputFailure) }
        }
    }

    func testTimeoutAndCancellationReapProcessAndRemoveDirectory() async throws {
        for cancelled in [false, true] {
            var stub = try StubCodexCLI(generation: "exec /bin/sleep 20")
            defer { stub.cleanup() }
            stub.runner.generationTimeout = cancelled ? 10 : 3
            let runner = stub.runner
            let path = stub.executable.path
            let task = Task { try await runner.generate(for: "正文", path: path, instructions: TitleGenerationService.titleInstructions) }
            for _ in 0..<500 where !FileManager.default.fileExists(atPath: stub.directory.appendingPathComponent("stdin").path) {
                try await Task.sleep(for: .milliseconds(10))
            }
            let pid = try XCTUnwrap(Int32(try stub.read("pid").trimmingCharacters(in: .whitespacesAndNewlines)))
            if cancelled { task.cancel() }
            do { _ = try await task.value; XCTFail("Expected interruption") }
            catch {
                if cancelled { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertTrue(error.localizedDescription.contains("超时")) }
            }
            XCTAssertEqual(kill(pid, 0), -1)
            XCTAssertEqual(errno, ESRCH)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: stub.directory.path).contains { $0.hasPrefix("PhrasePerch-Codex-") })
        }
    }
}
