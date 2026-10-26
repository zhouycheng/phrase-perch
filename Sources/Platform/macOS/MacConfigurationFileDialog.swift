import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacConfigurationFileDialog: ConfigurationFileDialog {
    static let configurationPackage = UTType(exportedAs: "local.PhrasePerch.configuration", conformingTo: .package)
    func chooseAttachments(multiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = multiple ? "添加附件" : "替换附件"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        return panel.runModal() == .OK ? panel.urls : []
    }
    func chooseApplications() -> [URL] {
        let panel = applicationPanel(allowsMultipleSelection: true)
        return panel.runModal() == .OK ? panel.urls : []
    }

    func chooseApplication() -> URL? {
        let panel = applicationPanel(allowsMultipleSelection: false)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func applicationPanel(allowsMultipleSelection: Bool) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        return panel
    }

    func chooseImport() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, Self.configurationPackage]
        panel.treatsFilePackagesAsDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseExport() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.configurationPackage]
        panel.nameFieldStringValue = "PhrasePerch.phraseperch"
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
