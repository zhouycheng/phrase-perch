import Foundation
import Observation

@MainActor @Observable
final class ConfigurationRepository {
    private(set) var configuration = AppConfiguration() {
        didSet {
            updateValidation()
            scheduleSave()
            notifyObservers()
        }
    }
    @ObservationIgnored private var observers: [UUID: () -> Void] = [:]
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
    private let disk: any ConfigurationStorage
    private var saveTask: Task<Void, Never>?
    private var loading = true

    init(directory: URL? = nil, storage: (any ConfigurationStorage)? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        disk =
            storage
            ?? JSONConfigurationStorage(
                directory: directory
                    ?? support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.FloatingInputBar"))
        Task { await load() }
    }

    func update(_ change: (inout AppConfiguration) -> Void) {
        var value = configuration
        change(&value)
        guard value != configuration else { return }
        configuration = value
    }

    @discardableResult
    func observe(_ callback: @escaping () -> Void) -> UUID {
        let token = UUID()
        observers[token] = callback
        return token
    }

    func removeObserver(_ token: UUID) { observers[token] = nil }

    private func notifyObservers() {
        for callback in Array(observers.values) { callback() }
    }

    private func load() async {
        do {
            configuration = try await disk.load()
            isReady = true
            clearIssues()
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

    private func clearIssues() {
        saveIssue = nil
        operationIssue = nil
    }

    private func didSave(_ capturedRevision: Int) {
        guard capturedRevision == revision else { return }
        savedRevision = capturedRevision
        saveIssue = nil
    }

    private func updateValidation() {
        do {
            try configuration.validate()
            validationMessage = nil
        } catch { validationMessage = error.localizedDescription }
    }

    private func scheduleSave() {
        guard !loading, isReady else { return }
        revision += 1
        saveTask?.cancel()
        guard validationMessage == nil else { return }
        let value = configuration
        let capturedRevision = revision
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                try await disk.save(value)
                didSave(capturedRevision)
            } catch is CancellationError {} catch {
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
            loading = true
            configuration = recovered
            loading = false
            isReady = true
            revision += 1
            savedRevision = revision
            clearIssues()
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
            loading = true
            configuration = config
            loading = false
            isReady = true
            revision += 1
            savedRevision = revision
            clearIssues()
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
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(value).write(to: url, options: .atomic)
            }.value
            if operationIssue?.operation == .exportFile { operationIssue = nil }
        } catch { report(.exportFile, message: error.localizedDescription) }
    }
}
