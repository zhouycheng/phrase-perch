import Foundation

@testable import PhrasePerch

@MainActor
final class StubAppEntryPlatform: AppEntryPlatform {
    var dockVisible = false
    var loginEnabled = false
    var failDockChanges = false
    var failLoginChanges = false
    private(set) var dockRequests: [Bool] = []
    private(set) var menuBarVisible = false
    private(set) var menuEnabled = false
    var onToggle: (() -> Void)?
    var onOpen: (() -> Void)?
    var onImport: (() -> Void)?
    var onExport: (() -> Void)?

    func setDockVisible(_ visible: Bool) {
        dockRequests.append(visible)
        if !failDockChanges { dockVisible = visible }
    }
    func setLoginEnabled(_ enabled: Bool) throws {
        if failLoginChanges { throw InputFailure("injected login failure") }
        loginEnabled = enabled
    }
    func setMenuBar(visible: Bool, enabled: Bool, toggle: @escaping () -> Void, open: @escaping () -> Void,
        importFile: @escaping () -> Void, exportFile: @escaping () -> Void) {
        menuBarVisible = visible
        menuEnabled = enabled
        onToggle = toggle
        onOpen = open
        onImport = importFile
        onExport = exportFile
    }
    func refreshMenu(enabled: Bool) { menuEnabled = enabled }
    func stop() { menuBarVisible = false }
}
