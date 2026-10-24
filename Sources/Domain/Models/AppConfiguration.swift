import CoreGraphics
import Foundation

struct AppConfiguration: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var profiles: [AppProfile] = []
    var preferences = Preferences()

    init(schemaVersion: Int = 1, profiles: [AppProfile] = [], preferences: Preferences = Preferences()) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, profiles, preferences }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else { throw InputFailure("不支持配置版本 \(version)") }
        schemaVersion = version
        profiles = try values.decode([AppProfile].self, forKey: .profiles)
        preferences = try values.decode(Preferences.self, forKey: .preferences)
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw InputFailure("不支持配置版本 \(schemaVersion)") }
        var identities = Set<String>()
        var ids = Set<UUID>()
        for profile in profiles {
            let identity = profile.application
            guard !(identity.bundleIdentifier ?? "").isEmpty || !(identity.fallbackBundlePath ?? "").isEmpty else {
                throw InputFailure("应用缺少身份")
            }
            guard identities.insert(identity.key).inserted, ids.insert(profile.id).inserted else {
                throw InputFailure("配置存在重复应用身份或 ID")
            }
            guard !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InputFailure("应用名称不能为空")
            }
            for group in profile.groups {
                guard ids.insert(group.id).inserted else { throw InputFailure("分组 ID 重复") }
                guard !group.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InputFailure("分组名称不能为空") }
            }
            try profile.validateHierarchy()
            for button in profile.buttons {
                guard ids.insert(button.id).inserted else { throw InputFailure("按钮 ID 重复") }
                try SnippetValidator.validate(button)
            }
        }
    }
}
