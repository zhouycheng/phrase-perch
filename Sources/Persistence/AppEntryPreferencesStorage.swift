import Foundation

enum AppEntryPreferencesStorage {
    static let silentLaunchKey = "PhrasePerch.silentLaunchEnabled"

    static func loadSilentLaunch(from defaults: UserDefaults = .standard) -> Bool {
        defaults.register(defaults: [silentLaunchKey: true])
        return defaults.bool(forKey: silentLaunchKey)
    }

    static func saveSilentLaunch(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: silentLaunchKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> AppEntryVisibility {
        defaults.register(defaults: [AppEntryVisibility.dockKey: false, AppEntryVisibility.menuBarKey: true])
        return AppEntryVisibility(
            dock: defaults.bool(forKey: AppEntryVisibility.dockKey),
            menuBar: defaults.bool(forKey: AppEntryVisibility.menuBarKey))
    }

    static func save(_ visibility: AppEntryVisibility, to defaults: UserDefaults = .standard) {
        defaults.set(visibility.dock, forKey: AppEntryVisibility.dockKey)
        defaults.set(visibility.menuBar, forKey: AppEntryVisibility.menuBarKey)
    }
}
