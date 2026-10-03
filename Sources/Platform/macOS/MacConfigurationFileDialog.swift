import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacConfigurationFileDialog: ConfigurationFileDialog {
    func chooseApplications() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    func chooseImport() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseExport() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PhrasePerch.json"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func confirmReplacement(profileCount: Int, snippetCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "替换现有配置？"
        alert.informativeText = "导入 \(profileCount) 个应用、\(snippetCount) 个按钮。替换前会备份现有配置。"
        alert.addButton(withTitle: "替换并备份")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
