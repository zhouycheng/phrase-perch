import CoreGraphics
import Foundation

struct Preferences: Codable, Equatable, Sendable {
    var isEnabled = true
    var clickModifier = ClickModifier.option
    var menuAnchorMode = MenuAnchorMode.mouse
    static let defaultTitleAPIBaseURL = "http://127.0.0.1:8317/v1"
    var titleAPIBaseURL = Self.defaultTitleAPIBaseURL
    var titleModel = ""
    var titleGenerationProvider = TitleGenerationProvider.cliProxyAPI
    var codexExecutablePath = ""
    init() {}
    private enum CodingKeys: String, CodingKey {
        case isEnabled, clickModifier, menuAnchorMode, titleAPIBaseURL, titleModel, titleGenerationProvider, codexExecutablePath
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        clickModifier = try values.decode(ClickModifier.self, forKey: .clickModifier)
        menuAnchorMode = try values.decodeIfPresent(MenuAnchorMode.self, forKey: .menuAnchorMode) ?? .mouse
        titleAPIBaseURL = try values.decodeIfPresent(String.self, forKey: .titleAPIBaseURL) ?? Self.defaultTitleAPIBaseURL
        titleModel = try values.decodeIfPresent(String.self, forKey: .titleModel) ?? ""
        titleGenerationProvider = try values.decodeIfPresent(TitleGenerationProvider.self, forKey: .titleGenerationProvider) ?? .cliProxyAPI
        codexExecutablePath = try values.decodeIfPresent(String.self, forKey: .codexExecutablePath) ?? ""
    }
}
