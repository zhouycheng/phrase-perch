import AppKit

enum ApplicationCatalog {
    @MainActor
    static func initialConfiguration() -> AppConfiguration {
        let candidates = [("Safari", "com.apple.Safari"), ("ChatGPT", "com.openai.chat")]
        let profiles = candidates.map { name, identifier in
            let local = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
                + FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
            let url = local.map { $0.appendingPathComponent("\(name).app") }
                .first { Bundle(url: $0) != nil }
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            let bundle = url.flatMap(Bundle.init(url:))
            return AppProfile(application: ApplicationIdentity(bundleIdentifier: bundle?.bundleIdentifier ?? identifier,
                fallbackBundlePath: url?.path), displayName: name, lastKnownBundlePath: url?.path)
        }
        return AppConfiguration(profiles: profiles)
    }
    static func runningApplications() -> [ApplicationChoice] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let url = app.bundleURL else { return nil }
            return ApplicationChoice(id: app.processIdentifier, name: app.localizedName ?? "应用", url: url)
        }
    }
    static func icon(at path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
}
