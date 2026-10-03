import SwiftUI

struct SnippetRingPreviewView<Actions: View>: View {
    let snippets: [Snippet]
    let selectedID: UUID?
    let select: (UUID) -> Void
    let requestDeletion: (UUID) -> Void
    let addSnippet: () -> Void
    let actions: (UUID) -> Actions
    var body: some View {
        GeometryReader { geometry in
            let layout = EditorRingLayout(size: geometry.size, count: snippets.count)
            if snippets.isEmpty {
                EmptyStateView(title: "添加文案", symbol: "text.badge.plus", action: addSnippet)
            } else {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                    let rect = layout.items[index]
                    SnippetButtonView(snippet: snippet, selected: selectedID == snippet.id, size: rect.size) {
                        select(snippet.id)
                    }
                    .contextMenu { actions(snippet.id) }
                    .position(x: rect.midX, y: rect.midY)
                    if selectedID == snippet.id {
                        Button(role: .destructive) {
                            requestDeletion(snippet.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                                .font(.system(size: 11)).frame(width: 60, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(.red)
                        .help("删除文案 \(snippet.title)")
                        .accessibilityLabel("删除选中的环形文案")
                        .position(x: rect.midX, y: rect.maxY + 14)
                    }
                }
            }
        }
    }
}
