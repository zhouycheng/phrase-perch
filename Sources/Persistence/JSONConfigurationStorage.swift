import Foundation
import Observation

actor JSONConfigurationStorage: ConfigurationStorage {
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
