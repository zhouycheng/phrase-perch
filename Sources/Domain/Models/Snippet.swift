import CoreGraphics
import Foundation

struct Snippet: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var content: SnippetContent
    var isEnabled: Bool

    init(id: UUID = UUID(), title: String, text: String, isEnabled: Bool = true) {
        self.init(id: id, title: title, content: .text(text), isEnabled: isEnabled)
    }
    init(id: UUID = UUID(), title: String, content: SnippetContent, isEnabled: Bool = true) {
        self.id = id; self.title = title; self.content = content; self.isEnabled = isEnabled
    }
    var text: String {
        get { if case .text(let text) = content { return text }; return "" }
        set { content = .text(newValue) }
    }
    var attachment: AttachmentReference? {
        if case .attachment(let file) = content { return file }
        return nil
    }
    private enum CodingKeys: String, CodingKey { case id, title, content, text, isEnabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        content = try values.decodeIfPresent(SnippetContent.self, forKey: .content)
            ?? .text(values.decode(String.self, forKey: .text))
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(content, forKey: .content)
        try values.encode(isEnabled, forKey: .isEnabled)
    }
}
