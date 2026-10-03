import Foundation

@MainActor
protocol ConfigurationFileDialog {
    func chooseApplications() -> [URL]
    func chooseImport() -> URL?
    func chooseExport() -> URL?
    func confirmReplacement(profileCount: Int, snippetCount: Int) -> Bool
}
