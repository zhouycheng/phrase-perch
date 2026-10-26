import Foundation

extension JSONConfigurationStorage {
    private var attachmentsDirectory: URL { directory.appendingPathComponent("attachments", isDirectory: true) }
    private func importDirectory(_ id: UUID) -> URL {
        directory.appendingPathComponent(".imports", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }
    private func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw InputFailure("附件目录无效") }
    }
    private func regularFileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else {
            throw InputFailure("请选择普通文件")
        }
        return Int64(size)
    }
    private func checkedAttachment(_ file: AttachmentReference, in root: URL) throws -> URL {
        try file.validate()
        let assets = root.appendingPathComponent("attachments", isDirectory: true)
        let folder = assets.appendingPathComponent(file.id.uuidString, isDirectory: true)
        try requireDirectory(root)
        try requireDirectory(assets)
        try requireDirectory(folder)
        let url = folder.appendingPathComponent(file.fileName)
        guard try regularFileSize(url) == file.byteCount else { throw InputFailure("附件文件大小已变化，请重新添加") }
        return url
    }
    private func copyAttachment(from source: URL, file: AttachmentReference, into root: URL) throws {
        try file.validate()
        let assets = root.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try requireDirectory(root)
        try requireDirectory(assets)
        let folder = assets.appendingPathComponent(file.id.uuidString, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw InputFailure("附件资源 ID 冲突") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(file.fileName))
            _ = try checkedAttachment(file, in: root)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
    func importAttachment(from url: URL) async throws -> AttachmentReference {
        let source = url.resolvingSymlinksInPath()
        let file = AttachmentReference(fileName: source.lastPathComponent, byteCount: try regularFileSize(source))
        try copyAttachment(from: source, file: file, into: directory)
        uncommittedAttachments.insert(file.id)
        return file
    }
    private func managedAttachmentURL(_ file: AttachmentReference) throws -> URL {
        do { return try checkedAttachment(file, in: directory) }
        catch { throw InputFailure("附件“\(file.fileName)”不可用，请重新选择文件") }
    }
    func attachmentURL(_ file: AttachmentReference) async throws -> URL { try managedAttachmentURL(file) }
    func retainAttachment(_ file: AttachmentReference) async throws -> URL {
        let url = try managedAttachmentURL(file)
        attachmentLeases[file.id, default: 0] += 1
        return url
    }
    func releaseAttachment(_ id: UUID) async {
        if let count = attachmentLeases[id], count > 1 { attachmentLeases[id] = count - 1 }
        else { attachmentLeases[id] = nil }
    }
    func abandonAttachment(_ id: UUID) async { uncommittedAttachments.remove(id) }

    func pruneAttachments(retaining ids: Set<UUID>, clipboardURLs: [URL]) async {
        var retained = ids.union(uncommittedAttachments).union(attachmentLeases.keys)
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                retained.formUnion(try decode(Data(contentsOf: file)).attachments.map(\.id))
            }
            for backup in try backups() { retained.formUnion(try decode(Data(contentsOf: backup)).attachments.map(\.id)) }
            for config in pendingImports.values { retained.formUnion(config.attachments.map(\.id)) }
            for url in clipboardURLs where url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == attachmentsDirectory.standardizedFileURL {
                if let id = UUID(uuidString: url.deletingLastPathComponent().lastPathComponent) { retained.insert(id) }
            }
            guard FileManager.default.fileExists(atPath: attachmentsDirectory.path) else { return }
            try requireDirectory(attachmentsDirectory)
            for folder in try FileManager.default.contentsOfDirectory(at: attachmentsDirectory, includingPropertiesForKeys: nil) {
                if let id = UUID(uuidString: folder.lastPathComponent), !retained.contains(id) {
                    try FileManager.default.removeItem(at: folder)
                }
            }
        } catch { /* Keep files when the retained references cannot be established. */ }
    }

    func readImport(_ url: URL) async throws -> ConfigurationImport {
        if url.pathExtension.lowercased() != "phraseperch" {
            guard try regularFileSize(url) <= 16 * 1024 * 1024 else { throw InputFailure("配置文件超过 16 MiB") }
            let config = try decode(Data(contentsOf: url))
            guard config.attachments.isEmpty else { throw InputFailure("包含附件的配置请通过备份包导入") }
            return ConfigurationImport(configuration: config)
        }
        try requireDirectory(url)
        let manifest = url.appendingPathComponent("configuration.json")
        guard try regularFileSize(manifest) <= 16 * 1024 * 1024 else { throw InputFailure("配置文件超过 16 MiB") }
        var config = try decode(Data(contentsOf: manifest))
        let token = UUID()
        let stage = importDirectory(token)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try requireDirectory(stage.deletingLastPathComponent())
        do {
            var replacements: [UUID: AttachmentReference] = [:]
            for original in Set(config.attachments) {
                let source = try checkedAttachment(original, in: url)
                let replacement = AttachmentReference(fileName: original.fileName, byteCount: original.byteCount)
                try copyAttachment(from: source, file: replacement, into: stage)
                replacements[original.id] = replacement
            }
            for profile in config.profiles.indices {
                for item in config.profiles[profile].buttons.indices {
                    if let original = config.profiles[profile].buttons[item].attachment, let replacement = replacements[original.id] {
                        config.profiles[profile].buttons[item].content = .attachment(replacement)
                    }
                }
            }
            pendingImports[token] = config
            return ConfigurationImport(configuration: config, stagingID: token)
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }
    func commitImport(_ prepared: ConfigurationImport) async throws {
        guard let token = prepared.stagingID else { try save(prepared.configuration); return }
        guard pendingImports[token] == prepared.configuration else { throw InputFailure("导入已失效，请重新选择备份包") }
        let stage = importDirectory(token)
        var moved: [URL] = []
        do {
            try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
            try requireDirectory(directory)
            try requireDirectory(attachmentsDirectory)
            for asset in Set(prepared.configuration.attachments) {
                _ = try checkedAttachment(asset, in: stage)
                let folder = attachmentsDirectory.appendingPathComponent(asset.id.uuidString, isDirectory: true)
                try FileManager.default.moveItem(at: stage.appendingPathComponent("attachments").appendingPathComponent(asset.id.uuidString), to: folder)
                moved.append(folder)
            }
            try save(prepared.configuration)
            pendingImports[token] = nil
            try? FileManager.default.removeItem(at: stage)
        } catch {
            for folder in moved { try? FileManager.default.removeItem(at: folder) }
            throw error
        }
    }
    func discardImport(_ prepared: ConfigurationImport) async {
        guard let token = prepared.stagingID, pendingImports.removeValue(forKey: token) != nil else { return }
        try? FileManager.default.removeItem(at: importDirectory(token))
    }
    func export(_ configuration: AppConfiguration, to url: URL) async throws {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        guard data.count <= 16 * 1024 * 1024 else { throw InputFailure("配置文件超过 16 MiB") }
        if url.pathExtension.lowercased() == "json" {
            guard configuration.attachments.isEmpty else { throw InputFailure("请导出包含附件的备份包") }
            try data.write(to: url, options: .atomic)
            return
        }
        let stage = url.deletingLastPathComponent().appendingPathComponent(".PhrasePerch-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stage) }
        try data.write(to: stage.appendingPathComponent("configuration.json"), options: .atomic)
        for asset in Set(configuration.attachments) {
            try copyAttachment(from: managedAttachmentURL(asset), file: asset, into: stage)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: stage)
        } else { try FileManager.default.moveItem(at: stage, to: url) }
    }
}
