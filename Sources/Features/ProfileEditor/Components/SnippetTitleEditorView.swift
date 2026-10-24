import SwiftUI

struct SnippetTitleEditorView: View {
    @Binding var text: String
    let issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("标题").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("输入文案标题", text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 18, weight: .medium))
                .lineLimit(1...3)
                .accessibilityLabel("文案标题")
            if let message = issue {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
