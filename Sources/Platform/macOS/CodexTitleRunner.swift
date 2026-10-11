import Darwin
import Foundation

struct CodexTitleRunner: Sendable {
    var environment = ProcessInfo.processInfo.environment
    var temporaryRoot = FileManager.default.temporaryDirectory
    var checkTimeout: TimeInterval = 5
    var generationTimeout: TimeInterval = 60

    func executable(at path: String) throws -> URL {
        let manual = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty {
            let expanded = (manual as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/"), isExecutable(expanded) else {
                throw InputFailure("Codex CLI 路径无效，请填写可执行文件的完整路径。")
            }
            return URL(fileURLWithPath: expanded)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = (environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { "\($0)/codex" } + [
                "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                "\(home)/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            ]
        guard let found = candidates.first(where: isExecutable) else {
            throw InputFailure("未找到 Codex CLI，请安装 Codex CLI 或填写程序路径。")
        }
        return URL(fileURLWithPath: found)
    }

    func check(at path: String) async throws -> String {
        let executable = try executable(at: path)
        return try await inDirectory { directory in
            let deadline = ProcessInfo.processInfo.systemUptime + checkTimeout
            let mainHelp = try await run(executable, ["--help"], directory: directory, deadline: deadline)
            guard mainHelp.stdout.contains("--no-daemon"), mainHelp.stdout.contains("--ask-for-approval") else {
                throw InputFailure("Codex CLI 版本不兼容，请更新后重新检测。")
            }
            let help = try await run(executable, ["exec", "--help"], directory: directory, deadline: deadline)
            for flag in ["--skip-git-repo-check", "--ephemeral", "--sandbox", "--color", "--config", "--disable"] {
                guard help.stdout.contains(flag) else {
                    throw InputFailure("Codex CLI 版本不兼容，请更新后重新检测。")
                }
            }
            let login = try await run(executable, ["login", "status"], directory: directory, deadline: deadline)
            let status = (login.stdout + login.stderr).lowercased()
            guard status.contains("logged in"), !status.contains("not logged in") else {
                throw InputFailure("Codex CLI 尚未登录，请在终端执行 codex login 后重新检测。")
            }
            return "Codex CLI 已就绪：\(executable.path)。使用已登录账号与默认模型。"
        }
    }

    func generate(for text: String, path: String, instructions: String) async throws -> String {
        let executable = try executable(at: path)
        return try await inDirectory { directory in
            let deadline = ProcessInfo.processInfo.systemUptime + generationTimeout
            let servers = try await run(executable, ["mcp", "list", "--json", "--disable", "plugins"],
                directory: directory, deadline: min(deadline, ProcessInfo.processInfo.systemUptime + checkTimeout))
            struct Server: Decodable { let name: String }
            guard let data = servers.stdout.data(using: .utf8),
                let names = try? JSONDecoder().decode([Server].self, from: data) else {
                throw InputFailure("无法读取 Codex MCP 配置，标题生成已停止，请检查 Codex CLI。")
            }
            var arguments = [
                "--no-daemon", "--ask-for-approval", "never", "exec", "--skip-git-repo-check",
                "--ephemeral", "--sandbox", "read-only", "--color", "never",
                "-c", "web_search=\"disabled\"", "-c", "project_doc_max_bytes=0",
            ]
            for feature in ["shell_tool", "unified_exec", "apps", "plugins", "hooks", "browser_use", "browser_use_external",
                "computer_use", "memories", "multi_agent", "multi_agent_v2", "image_generation", "shell_snapshot"] {
                arguments += ["--disable", feature]
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            // An inline TOML table preserves MCP names containing dots in CLI overrides.
            let disabledServers = try names.map { server in
                let key = String(decoding: try encoder.encode(server.name), as: UTF8.self)
                return "\(key)={enabled=false}"
            }.joined(separator: ",")
            arguments += ["-c", "mcp_servers={\(disabledServers)}"]
            arguments.append(instructions)
            let result = try await run(executable, arguments, input: Data(text.utf8), directory: directory, deadline: deadline)
            return result.stdout
        }
    }

    private func isExecutable(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory)
            && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    private func inDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = temporaryRoot.appendingPathComponent("PhrasePerch-Codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    private func run(_ executable: URL, _ arguments: [String], input: Data = Data(), directory: URL,
        deadline: TimeInterval) async throws -> CodexProcessResult {
        let execution = CodexProcessExecution()
        var processEnvironment = environment
        processEnvironment["PATH"] = ([executable.deletingLastPathComponent().path,
            processEnvironment["PATH"] ?? "", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
            .joined(separator: ":")
        let workerEnvironment = processEnvironment
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached {
                try execution.run(executable, arguments, input: input, directory: directory,
                    environment: workerEnvironment, deadline: deadline)
            }.value
        } onCancel: { execution.cancel() }
    }
}

private struct CodexProcessResult: Sendable {
    let stdout: String
    let stderr: String
}

// The lock only bridges task cancellation to the dedicated process worker.
private final class CodexProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    private var isCancelled: Bool { lock.withLock { cancelled } }

    func run(_ executable: URL, _ arguments: [String], input: Data, directory: URL,
        environment: [String: String], deadline: TimeInterval) throws -> CodexProcessResult {
        if isCancelled { throw CancellationError() }
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        defer {
            for pipe in [stdin, stdout, stderr] {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
        }
        do { try process.run() } catch {
            throw InputFailure("无法启动 Codex CLI，请检查程序路径与执行权限。")
        }
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        try? stdin.fileHandleForReading.close()
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        let inputFD = stdin.fileHandleForWriting.fileDescriptor
        let outputFD = stdout.fileHandleForReading.fileDescriptor
        let errorFD = stderr.fileHandleForReading.fileDescriptor
        for fd in [inputFD, outputFD, errorFD] { _ = fcntl(fd, F_SETFL, O_NONBLOCK) }
        _ = fcntl(inputFD, F_SETNOSIGPIPE, 1)
        var output = Data(), errors = Data(), offset = 0
        var inputClosed = false
        var buffer = [UInt8](repeating: 0, count: 8192)
        func drain(_ fd: Int32, into data: inout Data) throws {
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count > 0 {
                    guard data.count + count <= 1_048_576 else {
                        throw InputFailure("Codex CLI 输出过多，标题生成已停止。")
                    }
                    data.append(contentsOf: buffer.prefix(count))
                } else if count == 0 || errno == EAGAIN { return }
                else if errno != EINTR { throw InputFailure("读取 Codex CLI 输出失败，请重试。") }
            }
        }
        while true {
            if isCancelled { throw CancellationError() }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw InputFailure("Codex CLI 响应超时，请稍后重试。")
            }
            try drain(outputFD, into: &output)
            try drain(errorFD, into: &errors)
            if !process.isRunning { break }
            if !inputClosed {
                if offset < input.count {
                    let written = input.withUnsafeBytes { bytes in
                        Darwin.write(inputFD, bytes.baseAddress!.advanced(by: offset), min(input.count - offset, 8192))
                    }
                    if written > 0 { offset += written }
                    else if written < 0 && errno != EAGAIN && errno != EINTR {
                        throw InputFailure("向 Codex CLI 传入正文失败，请重试。")
                    }
                }
                if offset == input.count {
                    try? stdin.fileHandleForWriting.close()
                    inputClosed = true
                }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        try drain(outputFD, into: &output)
        try drain(errorFD, into: &errors)
        if isCancelled { throw CancellationError() }
        let errorText = String(decoding: errors, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let lower = errorText.lowercased()
            if lower.contains("not logged in") || lower.contains("unauthorized") || lower.contains("401") {
                throw InputFailure("Codex CLI 尚未登录或登录已失效，请在终端执行 codex login。")
            }
            if lower.contains("unexpected argument") || lower.contains("unknown variant") || lower.contains("unrecognized") {
                throw InputFailure("Codex CLI 版本或配置不兼容，请更新后重新检测。")
            }
            throw InputFailure("Codex CLI 请求失败（退出码 \(process.terminationStatus)），请检查登录、网络及默认模型配置。")
        }
        guard offset == input.count, let text = String(data: output, encoding: .utf8) else {
            throw InputFailure("Codex CLI 输入或输出不完整，请重试。")
        }
        return CodexProcessResult(stdout: text, stderr: errorText)
    }
}
