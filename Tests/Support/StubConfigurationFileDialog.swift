import Foundation

@testable import PhrasePerch

@MainActor
final class StubConfigurationFileDialog: ConfigurationFileDialog {
    var acceptsReplacement = false
    private(set) var proposedCounts: (profiles: Int, snippets: Int)?
    func chooseApplications() -> [URL] { [] }
    func chooseApplication() -> URL? { nil }
    func chooseImport() -> URL? { nil }
    func chooseExport() -> URL? { nil }
    func confirmReplacement(profileCount: Int, snippetCount: Int) -> Bool {
        proposedCounts = (profileCount, snippetCount)
        return acceptsReplacement
    }
}
