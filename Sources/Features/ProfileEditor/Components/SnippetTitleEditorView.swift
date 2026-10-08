import SwiftUI

struct SnippetTitleEditorView: View {
    @Binding var text: String
    let issue: String?
    var isGenerating = false
    var canGenerate = false
    var generationMessage: String?
    var generationHelp = ""
    var generate: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("标题").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if isGenerating { ProgressView().controlSize(.mini).accessibilityLabel("正在生成标题") }
                Button(isGenerating ? "生成中…" : "生成标题", action: generate)
                    .font(.system(size: 11)).disabled(!canGenerate).help(generationHelp)
            }
            TextField("输入文案标题", text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 18, weight: .medium))
                .lineLimit(1...3)
                .accessibilityLabel("文案标题")
            if let message = issue {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let message = generationMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .textSelection(.enabled).accessibilityLabel("标题生成提示：\(message)")
            }
        }
    }
}
