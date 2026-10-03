import Foundation

enum AppEntryPreferencesStorage {
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
