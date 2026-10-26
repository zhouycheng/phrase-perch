import Foundation

enum SnippetValidator {
    static func validate(_ snippet: Snippet) throws {
        if let message = titleIssue(snippet.title) { throw InputFailure(message) }
        switch snippet.content {
        case .text(let text):
            if let message = textIssue(text) { throw InputFailure(message) }
        case .attachment(let file):
            try file.validate()
        }
    }
    static func titleIssue(_ title: String) -> String? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "请填写内容标题" : nil
    }
    static func textIssue(_ text: String) -> String? {
        if text.isEmpty { return "请填写文案正文" }
        if text.utf8.count > 64 * 1024 { return "正文超过 64 KiB，请缩短内容" }
        if text.unicodeScalars.contains(where: { scalar in
            (scalar.value < 32 && ![9, 10, 13].contains(scalar.value)) || (127...159).contains(scalar.value)
        }) {
            return "正文含不支持的控制字符"
        }
        return nil
    }
}
