import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
let entryVisibility = AppEntryPreferencesStorage.load()
application.setActivationPolicy(entryVisibility.dock ? .regular : .accessory)
application.run()
