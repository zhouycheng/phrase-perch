import CoreGraphics
import Foundation

struct Preferences: Codable, Equatable, Sendable {
    var isEnabled = true
    var clickModifier = ClickModifier.option
    var menuAnchorMode = MenuAnchorMode.mouse
    init() {}
    private enum CodingKeys: String, CodingKey { case isEnabled, clickModifier, menuAnchorMode }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        clickModifier = try values.decode(ClickModifier.self, forKey: .clickModifier)
        menuAnchorMode = try values.decodeIfPresent(MenuAnchorMode.self, forKey: .menuAnchorMode) ?? .mouse
    }
}
