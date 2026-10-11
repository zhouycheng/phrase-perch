import Foundation

enum TitleGenerationProvider: String, Codable, CaseIterable, Sendable {
    case cliProxyAPI
    case codexCLI

    var displayName: String {
        switch self {
        case .cliProxyAPI: "CLIProxyAPI"
        case .codexCLI: "Codex CLI"
        }
    }
}
