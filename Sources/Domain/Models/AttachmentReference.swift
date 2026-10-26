import Foundation

struct AttachmentReference: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var fileName: String
    var byteCount: Int64

    func validate() throws {
        guard !fileName.isEmpty, fileName != ".", fileName != "..",
            !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains(":"),
            !fileName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), byteCount >= 0
        else { throw InputFailure("附件信息无效") }
    }
}
