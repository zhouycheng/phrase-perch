import Foundation
import Observation

actor ConfigurationDisk {
    let directory: URL
    var file: URL { directory.appendingPathComponent("configuration.json") }
    init(directory: URL) { self.directory = directory }

    func decode(_ data: Data) throws -> AppConfiguration {
        guard data.count <= 16 * 1024 * 1024 else { throw InputFailure("配置文件超过 16 MiB") }
        let config = try JSONDecoder().decode(AppConfiguration.self, from: data)
        try config.validate()
        return config
    }
    func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: file.path) else { return AppConfiguration() }
        return try decode(Data(contentsOf: file))
    }
    func backups() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("backup-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func latestBackup() throws -> AppConfiguration {
        for url in try backups() {
            if let config = try? decode(Data(contentsOf: url)) { return config }
        }
        throw InputFailure("没有可恢复的有效备份")
    }
    func save(_ config: AppConfiguration) throws {
        try config.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        guard data.count <= 16 * 1024 * 1024 else { throw InputFailure("配置总大小超过 16 MiB") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let old = try? Data(contentsOf: file), old != data {
            let prefix = (try? decode(old)) != nil ? "backup" : "damaged"
            let name = "\(prefix)-\(String(format: "%.6f", Date().timeIntervalSince1970))-\(UUID().uuidString).json"
            try old.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
        // Backup cleanup failure does not change the outcome of a committed save.
        if let files = try? backups() { for url in files.dropFirst(3) { try? FileManager.default.removeItem(at: url) } }
    }
}

@MainActor @Observable
final class ConfigurationStore {
    var configuration = AppConfiguration() { didSet { scheduleSave(); onChange?() } }
    @ObservationIgnored var onChange: (() -> Void)?
    var errorMessage: String?
    private(set) var isReady = false
    private(set) var revision = 0
    private(set) var savedRevision = 0
    var saveStatus: String {
        if errorMessage != nil { return "保存失败" }
        if !isReady { return "正在加载" }
        return savedRevision == revision ? "已保存" : "正在保存…"
    }
    private let disk: ConfigurationDisk
    private var saveTask: Task<Void, Never>?
    private var loading = true

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        disk = ConfigurationDisk(directory: directory ?? support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.FloatingInputBar"))
        Task {
            do {
                configuration = try await disk.load()
                isReady = true
            } catch { errorMessage = "配置读取失败，原文件已保留：\(error.localizedDescription)" }
            loading = false
        }
    }

    private func scheduleSave() {
        guard !loading, isReady else { return }
        revision += 1
        saveTask?.cancel()
        let value = configuration, capturedRevision = revision
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                try await disk.save(value)
                if capturedRevision == revision { savedRevision = capturedRevision; errorMessage = nil }
            } catch is CancellationError { } catch {
                errorMessage = "保存失败，草稿仍在内存中：\(error.localizedDescription)"
            }
        }
    }

    func flush() async -> Bool {
        saveTask?.cancel()
        do {
            let capturedRevision = revision
            try await disk.save(configuration)
            if capturedRevision == revision { savedRevision = capturedRevision; errorMessage = nil }
            return true
        }
        catch { errorMessage = "保存失败：\(error.localizedDescription)"; return false }
    }

    func restoreBackup() async {
        do {
            let recovered = try await disk.latestBackup()
            try await disk.save(recovered)
            loading = true; configuration = recovered; loading = false
            isReady = true; revision += 1; savedRevision = revision; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func readImport(_ url: URL) async throws -> AppConfiguration {
        let data = try await Task.detached { try Data(contentsOf: url) }.value
        return try await disk.decode(data)
    }

    func replace(with config: AppConfiguration) async {
        saveTask?.cancel()
        do {
            try await disk.save(config)
            loading = true; configuration = config; loading = false
            isReady = true; revision += 1; savedRevision = revision; errorMessage = nil
        } catch { errorMessage = "导入失败，现有配置保留：\(error.localizedDescription)" }
    }

    func export(to url: URL) async {
        let value = configuration
        do {
            try value.validate()
            try await Task.detached {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(value).write(to: url, options: .atomic)
            }.value
        } catch { errorMessage = error.localizedDescription }
    }
}
