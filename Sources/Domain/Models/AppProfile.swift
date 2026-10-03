import CoreGraphics
import Foundation

struct AppProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var application: ApplicationIdentity
    var displayName: String
    var lastKnownBundlePath: String?
    var isEnabled = true
    var displayMode = DisplayMode.modifierClick
    var buttons: [Snippet] = []

    func canTrigger(_ source: HoldMenuSession.Trigger) -> Bool {
        guard isEnabled, buttons.contains(where: \.isEnabled) else { return false }
        switch displayMode {
        case .modifierClick: return source == .modifier
        case .shortcutOnly: return source == .shortcut
        }
    }
}
