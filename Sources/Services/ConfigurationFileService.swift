import Foundation
import Observation

@MainActor @Observable
final class ConfigurationFileService {
    let store: ConfigurationRepository
    private let editing: ProfileEditingService
    private let dialog: any ConfigurationFileDialog
    var notice = ""
    var onInvalidate: (() -> Void)?
    init(store: ConfigurationRepository, editing: ProfileEditingService, dialog: any ConfigurationFileDialog) {
        self.store = store
        self.editing = editing
        self.dialog = dialog
    }
    func addApplication(_ url: URL) {
        guard let application = applicationDetails(at: url) else {
            notice = "请选择有效的 .app 应用包"
            return
        }
        guard !store.configuration.profiles.contains(where: { $0.application.key == application.identity.key }) else {
            notice = "此应用已在列表中。"
            return
        }
        _ = editing.addProfile(
            AppProfile(
                application: application.identity, displayName: application.name,
                lastKnownBundlePath: url.path,
                buttons: [
                    Snippet(title: "继续", text: "按照刚才确定的方案继续执行。"),
                    Snippet(title: "检查", text: "请检查当前内容，指出遗漏、冲突和需要修改的地方。"),
                    Snippet(title: "解释", text: "请解释其中的原理，并给出具体示例。"),
                ]))
    }

    func duplicateProfile(_ profileID: UUID) {
        guard let source = store.configuration.profiles.first(where: { $0.id == profileID }),
            let url = dialog.chooseApplication()
        else { return }
        guard let application = applicationDetails(at: url) else {
            notice = "请选择有效的 .app 应用包"
            return
        }
        guard !store.configuration.profiles.contains(where: { $0.application.key == application.identity.key }) else {
            notice = "此应用已在列表中。"
            return
        }
        var copy = source
        copy.id = UUID()
        copy.application = application.identity
        copy.displayName = application.name
        copy.lastKnownBundlePath = url.path
        copy.buttons = source.buttons.map { button in
            var copy = button
            copy.id = UUID()
            return copy
        }
        _ = editing.addProfile(copy)
    }

    private func applicationDetails(at url: URL) -> (identity: ApplicationIdentity, name: String)? {
        guard let bundle = Bundle(url: url), url.pathExtension == "app" else { return nil }
        let identity = ApplicationIdentity(bundleIdentifier: bundle.bundleIdentifier, fallbackBundlePath: url.path)
        let name =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return (identity, name)
    }

    func chooseApplications() {
        dialog.chooseApplications().forEach(addApplication)
    }

    func importConfiguration() {
        onInvalidate?()
        guard let url = dialog.chooseImport() else { return }
        Task { await importConfiguration(from: url) }
    }

    func importConfiguration(from url: URL) async {
        do {
            let config = try await store.readImport(url)
            if dialog.confirmReplacement(
                profileCount: config.profiles.count,
                snippetCount: config.profiles.reduce(0) { $0 + $1.buttons.count })
            {
                await store.replace(with: config)
            }
        } catch { store.report(.importFile, message: error.localizedDescription) }
    }

    func exportConfiguration() {
        if let url = dialog.chooseExport() { Task { await store.export(to: url) } }
    }
}
