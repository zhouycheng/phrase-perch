import Foundation
import UniformTypeIdentifiers

struct ClipboardFile: Sendable {
    let url: URL
    let imageType: String?
    let imageData: Data?

    init(url: URL) throws {
        self.url = url
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
        guard url.isFileURL, values.isRegularFile == true else { throw InputFailure("附件文件不可用") }
        if let type = values.contentType, type.conforms(to: .image) {
            imageType = type.identifier
            imageData = try Data(contentsOf: url, options: .mappedIfSafe)
        } else { imageType = nil; imageData = nil }
    }
}
