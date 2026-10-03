import AppKit

struct ApplicationMetadata {
    let version: String
    let icon: NSImage
    static func current() -> ApplicationMetadata {
        ApplicationMetadata(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            icon: ApplicationCatalog.icon(at: Bundle.main.bundlePath))
    }
}
