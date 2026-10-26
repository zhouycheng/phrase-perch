import Foundation
import Observation

@MainActor @Observable
final class ConfigurationRepository {
    private(set) var configuration = AppConfiguration() {
        didSet {
            updateValidation()
            scheduleSave()
            notifyObservers()
            let removed = Set(oldValue.attachments.map(\.id)).subtracting(configuration.attachments.map(\.id))
            if !removed.isEmpty {
                Task {
                    for id in removed where !configuration.attachments.contains(where: { $0.id == id }) {
                        await disk.abandonAttachment(id)
                    }
                    await cleanupAttachments()
                }
            }
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
    @ObservationIgnored var clipboardFileURLs: () -> [URL] = { [] }
    private var saveTask: Task<Void, Never>?
    private var loading = true

    init(directory: URL? = nil, storage: (any ConfigurationStorage)? = nil, initialConfiguration: AppConfiguration = AppConfiguration()) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        disk =
            storage
            ?? JSONConfigurationStorage(
                directory: directory
                    ?? support.appendingPathComponent("local.PhrasePerch"),
                initialConfiguration: initialConfiguration)
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
        if isReady { await cleanupAttachments() }
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
                await cleanupAttachments()
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
            await cleanupAttachments()
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

    func readImport(_ url: URL) async throws -> ConfigurationImport {
        try await disk.readImport(url)
    }
    func discardImport(_ prepared: ConfigurationImport) async { await disk.discardImport(prepared) }
    func importAttachment(from url: URL) async throws -> AttachmentReference { try await disk.importAttachment(from: url) }
    func attachmentURL(_ file: AttachmentReference) async throws -> URL { try await disk.attachmentURL(file) }
    func retainAttachment(_ file: AttachmentReference) async throws -> URL { try await disk.retainAttachment(file) }
    func releaseAttachment(_ id: UUID) async { await disk.releaseAttachment(id) }
    func abandonAttachment(_ id: UUID) async {
        await disk.abandonAttachment(id)
        await cleanupAttachments()
    }
    func cleanupAttachments() async {
        await disk.pruneAttachments(retaining: Set(configuration.attachments.map(\.id)), clipboardURLs: clipboardFileURLs())
    }
    func replace(with prepared: ConfigurationImport) async {
        saveTask?.cancel()
        do {
            try await disk.commitImport(prepared)
            acceptReplacement(prepared.configuration)
            await cleanupAttachments()
        } catch {
            await disk.discardImport(prepared)
            report(.importFile, message: "导入失败，现有配置保留：\(error.localizedDescription)")
            if isReady, revision != savedRevision { scheduleSave() }
        }
    }
    private func acceptReplacement(_ config: AppConfiguration) {
        loading = true
        configuration = config
        loading = false
        isReady = true
        revision += 1
        savedRevision = revision
        clearIssues()
    }

    func replace(with config: AppConfiguration) async {
        saveTask?.cancel()
        do {
            try await disk.save(config)
            acceptReplacement(config)
            await cleanupAttachments()
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
            try await disk.export(value, to: url)
            if operationIssue?.operation == .exportFile { operationIssue = nil }
        } catch { report(.exportFile, message: error.localizedDescription) }
    }
}
