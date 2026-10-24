import Foundation

struct Preferences: Codable, Equatable, Sendable {
    var copyOnInsert = true
    var isEnabled = true
    var clickModifier = ClickModifier.option
    var menuAnchorMode = MenuAnchorMode.mouse

    init() {}
    private enum CodingKeys: String, CodingKey {
        case copyOnInsert, isEnabled, clickModifier, menuAnchorMode
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        copyOnInsert = try values.decode(Bool.self, forKey: .copyOnInsert)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        clickModifier = try values.decode(ClickModifier.self, forKey: .clickModifier)
        menuAnchorMode = try values.decode(MenuAnchorMode.self, forKey: .menuAnchorMode)
    }
}
