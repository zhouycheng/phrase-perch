import Foundation

protocol ConfigurationStorage: Sendable {
    func load() async throws -> AppConfiguration
    func decode(_ data: Data) async throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) async throws
    func latestBackup() async throws -> AppConfiguration
}
