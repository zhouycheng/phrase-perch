import Foundation

@MainActor
protocol ConfigurationFileDialog {
    func chooseApplications() -> [URL]
    func chooseApplication() -> URL?
    func chooseAttachments(multiple: Bool) -> [URL]
    func chooseImport() -> URL?
    func chooseExport() -> URL?
    func confirmReplacement(profileCount: Int, snippetCount: Int) -> Bool
}

extension ConfigurationFileDialog {
    func chooseAttachments(multiple: Bool) -> [URL] { [] }
}
