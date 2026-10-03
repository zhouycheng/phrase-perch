import CoreGraphics
import Foundation

struct ApplicationIdentity: Codable, Hashable, Sendable {
    var bundleIdentifier: String?
    var fallbackBundlePath: String?
    var key: String {
        if let id = bundleIdentifier, !id.isEmpty { return "bundle:\(id)" }
        return
            "path:\(URL(fileURLWithPath: fallbackBundlePath ?? "").standardizedFileURL.resolvingSymlinksInPath().path)"
    }
}
