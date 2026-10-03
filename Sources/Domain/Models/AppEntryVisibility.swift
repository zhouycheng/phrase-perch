import CoreGraphics
import Foundation

struct AppEntryVisibility: Equatable {
    private(set) var dock: Bool
    private(set) var menuBar: Bool

    static let dockKey = "PhrasePerch.dockIconVisible"
    static let menuBarKey = "PhrasePerch.menuBarIconVisible"

    init(dock: Bool = false, menuBar: Bool = true) {
        self.dock = dock
        self.menuBar = menuBar || !dock
    }

    mutating func setDock(_ visible: Bool) {
        guard visible || menuBar else { return }
        dock = visible
    }

    mutating func setMenuBar(_ visible: Bool) {
        guard visible || dock else { return }
        menuBar = visible
    }

}
