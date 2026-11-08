import SwiftUI

struct SnippetBodyEditorView: View {
    @Binding var text: String
    let issue: String?
    @State private var isEditing: Bool

    init(text: Binding<String>, issue: String?) {
        _text = text
        self.issue = issue
        _isEditing = State(initialValue: text.wrappedValue.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("正文").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 2) {
                    modeButton("编辑", editing: true)
                    modeButton("预览", editing: false)
                }
                .padding(3)
                .background(Color.white.opacity(0.065), in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityLabel("正文显示模式")
            }
            SnippetBodyTextView(text: $text, isEditing: $isEditing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message = issue {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func modeButton(_ title: String, editing: Bool) -> some View {
        Button { isEditing = editing } label: {
            Text(title).font(.system(size: 11, weight: isEditing == editing ? .medium : .regular))
                .foregroundStyle(isEditing == editing ? .primary : .secondary)
                .frame(width: 43, height: 20)
                .background(isEditing == editing ? Color.white.opacity(0.14) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)正文")
        .accessibilityAddTraits(isEditing == editing ? .isSelected : [])
    }
}
