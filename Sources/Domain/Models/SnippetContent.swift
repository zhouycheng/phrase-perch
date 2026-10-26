import Foundation

enum SnippetContent: Codable, Equatable, Sendable {
    case text(String)
    case attachment(AttachmentReference)

    private enum Kind: String, Codable { case text, attachment }
    private enum CodingKeys: String, CodingKey { case kind, text, attachment }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .text: self = .text(try values.decode(String.self, forKey: .text))
        case .attachment: self = .attachment(try values.decode(AttachmentReference.self, forKey: .attachment))
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try values.encode(Kind.text, forKey: .kind)
            try values.encode(text, forKey: .text)
        case .attachment(let file):
            try values.encode(Kind.attachment, forKey: .kind)
            try values.encode(file, forKey: .attachment)
        }
    }
}
