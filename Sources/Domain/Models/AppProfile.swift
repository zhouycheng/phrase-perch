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

    var groups: [SnippetGroup] = []
    var rootNodes: [MenuNode]

    private enum CodingKeys: String, CodingKey {
        case id, application, displayName, lastKnownBundlePath, isEnabled, displayMode, buttons, groups, rootNodes
    }
    init(id: UUID = UUID(), application: ApplicationIdentity, displayName: String,
         lastKnownBundlePath: String? = nil, isEnabled: Bool = true,
         displayMode: DisplayMode = .modifierClick, buttons: [Snippet] = [],
         groups: [SnippetGroup] = [], rootNodes: [MenuNode]? = nil) {
        self.id = id; self.application = application; self.displayName = displayName
        self.lastKnownBundlePath = lastKnownBundlePath; self.isEnabled = isEnabled
        self.displayMode = displayMode; self.buttons = buttons; self.groups = groups; self.rootNodes = rootNodes ?? buttons.map { MenuNode(kind: .snippet, id: $0.id) }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        application = try c.decode(ApplicationIdentity.self, forKey: .application)
        displayName = try c.decode(String.self, forKey: .displayName)
        lastKnownBundlePath = try c.decodeIfPresent(String.self, forKey: .lastKnownBundlePath)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        displayMode = try c.decode(DisplayMode.self, forKey: .displayMode)
        buttons = try c.decode([Snippet].self, forKey: .buttons)
        groups = try c.decode([SnippetGroup].self, forKey: .groups)
        rootNodes = try c.decode([MenuNode].self, forKey: .rootNodes)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(application, forKey: .application)
        try c.encode(displayName, forKey: .displayName); try c.encodeIfPresent(lastKnownBundlePath, forKey: .lastKnownBundlePath)
        try c.encode(isEnabled, forKey: .isEnabled); try c.encode(displayMode, forKey: .displayMode)
        try c.encode(buttons, forKey: .buttons); try c.encode(groups, forKey: .groups); try c.encode(rootNodes, forKey: .rootNodes)
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.application == rhs.application && lhs.displayName == rhs.displayName
            && lhs.lastKnownBundlePath == rhs.lastKnownBundlePath && lhs.isEnabled == rhs.isEnabled
            && lhs.displayMode == rhs.displayMode && lhs.buttons == rhs.buttons && lhs.groups == rhs.groups && lhs.rootNodes == rhs.rootNodes
    }
    func canTrigger(_ source: HoldMenuSession.Trigger) -> Bool {
        guard isEnabled, !enabledNodes().isEmpty else { return false }
        switch displayMode {
        case .modifierClick: return source == .modifier
        case .shortcutOnly: return source == .shortcut
        case .both: return true
        }
    }
}
