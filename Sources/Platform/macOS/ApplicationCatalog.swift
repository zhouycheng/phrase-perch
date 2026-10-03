import AppKit

enum ApplicationCatalog {
    static func runningApplications() -> [ApplicationChoice] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let url = app.bundleURL else { return nil }
            return ApplicationChoice(id: app.processIdentifier, name: app.localizedName ?? "应用", url: url)
        }
    }
    static func icon(at path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
}
