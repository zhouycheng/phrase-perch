import Foundation

enum SnippetValidator {
    static func validate(_ snippet: Snippet) throws {
        if let message = SnippetValidator.titleIssue(snippet.title) ?? SnippetValidator.textIssue(snippet.text) {
            throw InputFailure(message)
        }
    }
    static func titleIssue(_ title: String) -> String? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "请填写文案标题" : nil
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
