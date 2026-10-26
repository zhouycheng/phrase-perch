import Foundation

protocol ConfigurationStorage: Sendable {
    func load() async throws -> AppConfiguration
    func decode(_ data: Data) async throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) async throws
    func latestBackup() async throws -> AppConfiguration
    func importAttachment(from url: URL) async throws -> AttachmentReference
    func attachmentURL(_ file: AttachmentReference) async throws -> URL
    func retainAttachment(_ file: AttachmentReference) async throws -> URL
    func releaseAttachment(_ id: UUID) async
    func abandonAttachment(_ id: UUID) async
    func pruneAttachments(retaining ids: Set<UUID>, clipboardURLs: [URL]) async
    func readImport(_ url: URL) async throws -> ConfigurationImport
    func commitImport(_ prepared: ConfigurationImport) async throws
    func discardImport(_ prepared: ConfigurationImport) async
    func export(_ configuration: AppConfiguration, to url: URL) async throws
}

extension ConfigurationStorage {
    func importAttachment(from url: URL) async throws -> AttachmentReference { throw InputFailure("附件存储不可用") }
    func attachmentURL(_ file: AttachmentReference) async throws -> URL { throw InputFailure("附件存储不可用") }
    func retainAttachment(_ file: AttachmentReference) async throws -> URL { try await attachmentURL(file) }
    func releaseAttachment(_ id: UUID) async {}
    func abandonAttachment(_ id: UUID) async {}
    func pruneAttachments(retaining ids: Set<UUID>, clipboardURLs: [URL]) async {}
    func readImport(_ url: URL) async throws -> ConfigurationImport {
        let data = try await Task.detached { try Data(contentsOf: url) }.value
        let config = try await decode(data)
        guard config.attachments.isEmpty else { throw InputFailure("包含附件的配置请通过备份包导入") }
        return ConfigurationImport(configuration: config)
    }
    func commitImport(_ prepared: ConfigurationImport) async throws { try await save(prepared.configuration) }
    func discardImport(_ prepared: ConfigurationImport) async {}
    func export(_ configuration: AppConfiguration, to url: URL) async throws {
        guard configuration.attachments.isEmpty else { throw InputFailure("请导出包含附件的备份包") }
        try configuration.validate()
        try await Task.detached {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: url, options: .atomic)
        }.value
    }
}
