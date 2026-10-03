import SwiftUI

struct SnippetBodyEditorView: View {
    @Binding var text: String
    let issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("正文").font(.system(size: 11)).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineSpacing(4).scrollContentBackground(.hidden)
                // NSTextView adds 5 pt of line-fragment padding on each side.
                .padding(.horizontal, -5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("文案正文")
            if let message = issue {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
