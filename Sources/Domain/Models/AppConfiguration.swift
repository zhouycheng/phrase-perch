import CoreGraphics
import Foundation

struct AppConfiguration: Codable, Equatable, Sendable {
    var schemaVersion = 2
    var profiles: [AppProfile] = []
    var preferences = Preferences()

    func validate() throws {
        guard schemaVersion == 2 else { throw InputFailure("不支持配置版本 \(schemaVersion)") }
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
            for button in profile.buttons {
                guard ids.insert(button.id).inserted else { throw InputFailure("按钮 ID 重复") }
                try SnippetValidator.validate(button)
            }
        }
    }
}
