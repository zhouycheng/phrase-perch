import Foundation

@testable import PhrasePerch

struct StubCodexCLI {
    let directory: URL
    let executable: URL
    var runner: CodexTitleRunner

    init(generation: String = "printf '代码解释\\n'", mcp: String = "printf '[{\"name\":\"test.server\"}]'",
        login: String = "printf 'Logged in using ChatGPT\\n' >&2", help: String = "printf '%s\\n' --skip-git-repo-check --ephemeral --sandbox --color --config --disable") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        executable = directory.appendingPathComponent("tool space/codex")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        case "$1" in
            --help) printf '%s\\n' --no-daemon --ask-for-approval; exit 0 ;;
            mcp) \(mcp); exit $? ;;
            login) \(login); exit $? ;;
            exec) \(help); exit $? ;;
        esac
        printf '%s\\n' "$@" > "$PHRASEPERCH_CODEX_TEST_LOG/arguments"
        pwd > "$PHRASEPERCH_CODEX_TEST_LOG/cwd"
        printf '%s\\n' "$$" > "$PHRASEPERCH_CODEX_TEST_LOG/pid"
        cat > "$PHRASEPERCH_CODEX_TEST_LOG/stdin"
        \(generation)
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        runner = CodexTitleRunner()
        runner.environment["PHRASEPERCH_CODEX_TEST_LOG"] = directory.path
        runner.temporaryRoot = directory
    }

    func read(_ name: String) throws -> String { try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
