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

struct ConfigurationIssue: Equatable {
    enum Operation: String {
        case load = "读取失败", save = "保存失败", recovery = "恢复失败"
        case importFile = "导入失败", exportFile = "导出失败"
    }
    let operation: Operation
    let message: String
}

@MainActor @Observable
final class ConfigurationStore {
    var configuration = AppConfiguration() { didSet { updateValidation(); scheduleSave(); onChange?() } }
    @ObservationIgnored var onChange: (() -> Void)?
    private(set) var saveIssue: ConfigurationIssue?
    private var operationIssue: ConfigurationIssue?
    var issue: ConfigurationIssue? { saveIssue ?? operationIssue }
    private(set) var isReady = false
    private(set) var revision = 0
    private(set) var savedRevision = 0
    private(set) var validationMessage: String?
    // Used by the save-before-quit flow; field validation is not a disk failure.
    var errorMessage: String? { validationMessage ?? issue?.message }
    var saveStatus: String {
        if !isReady { return issue == nil ? "正在加载" : "读取失败" }
        if validationMessage != nil { return "待补全" }
        if saveIssue != nil { return "保存失败" }
        return savedRevision == revision ? "已保存" : "正在保存…"
    }
    private let disk: ConfigurationDisk
    private var saveTask: Task<Void, Never>?
    private var loading = true

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        disk = ConfigurationDisk(directory: directory ?? support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.FloatingInputBar"))
        Task { await load() }
    }

    private func load() async {
        do {
            configuration = try await disk.load()
            isReady = true; clearIssues()
        } catch { report(.load, message: "配置读取失败，原文件已保留：\(error.localizedDescription)") }
        loading = false
    }

    func retryLoad() async {
        guard !isReady, !loading else { return }
        loading = true
        await load()
    }

    func report(_ operation: ConfigurationIssue.Operation, message: String) {
        let reported = ConfigurationIssue(operation: operation, message: message)
        if operation == .save { saveIssue = reported } else { operationIssue = reported }
    }

    private func clearIssues() { saveIssue = nil; operationIssue = nil }

    private func didSave(_ capturedRevision: Int) {
        guard capturedRevision == revision else { return }
        savedRevision = capturedRevision
        saveIssue = nil
    }

    private func updateValidation() {
        do { try configuration.validate(); validationMessage = nil }
        catch { validationMessage = error.localizedDescription }
    }

    private func scheduleSave() {
        guard !loading, isReady else { return }
        revision += 1
        saveTask?.cancel()
        guard validationMessage == nil else { return }
        let value = configuration, capturedRevision = revision
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                try await disk.save(value)
                didSave(capturedRevision)
            } catch is CancellationError { } catch {
                guard capturedRevision == revision else { return }
                report(.save, message: "保存失败，草稿仍在内存中：\(error.localizedDescription)")
            }
        }
    }

    func flush() async -> Bool {
        saveTask?.cancel()
        guard isReady, validationMessage == nil else { return false }
        let capturedRevision = revision
        do {
            try await disk.save(configuration)
            didSave(capturedRevision)
            return capturedRevision == revision
        } catch {
            if capturedRevision == revision { report(.save, message: "保存失败：\(error.localizedDescription)") }
            return false
        }
    }

    func restoreBackup() async {
        saveTask?.cancel()
        do {
            let recovered = try await disk.latestBackup()
            try await disk.save(recovered)
            loading = true; configuration = recovered; loading = false
            isReady = true; revision += 1; savedRevision = revision; clearIssues()
        } catch {
            report(.recovery, message: error.localizedDescription)
            if isReady, revision != savedRevision { scheduleSave() }
        }
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
            isReady = true; revision += 1; savedRevision = revision; clearIssues()
        } catch {
            report(.importFile, message: "导入失败，现有配置保留：\(error.localizedDescription)")
            if isReady, revision != savedRevision { scheduleSave() }
        }
    }

    func export(to url: URL) async {
        guard isReady else { return }
        let value = configuration
        do {
            try value.validate()
            try await Task.detached {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(value).write(to: url, options: .atomic)
            }.value
            if operationIssue?.operation == .exportFile { operationIssue = nil }
        } catch { report(.exportFile, message: error.localizedDescription) }
    }
}
