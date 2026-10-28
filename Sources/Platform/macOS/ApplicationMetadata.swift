import AppKit

struct ApplicationMetadata {
    static let repositoryURL = URL(string: "https://github.com/zhouycheng/phrase-perch")!
    static let authorEmailURL = URL(string: "mailto:justinzhouself@gmail.com")!
    static let feedbackURL = repositoryURL.appendingPathComponent("issues")
    static let releaseNotesURL = repositoryURL.appendingPathComponent("releases")

    let version: String
    let icon: NSImage
    static func current() -> ApplicationMetadata {
        ApplicationMetadata(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            icon: ApplicationCatalog.icon(at: Bundle.main.bundlePath))
    }
}
