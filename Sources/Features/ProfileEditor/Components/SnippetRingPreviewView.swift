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
            let layout = EditorRingLayout(size: geometry.size, count: snippets.count, buttonWidth: snippetButtonWidth(for: snippets.map(\.title)))
            if snippets.isEmpty {
                EmptyStateView(title: "添加文案", symbol: "text.badge.plus", action: addSnippet)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(.secondary)
                            .position(x: layout.canvasSize.width / 2, y: layout.canvasSize.height / 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        ForEach(Array(zip(snippets, layout.items)), id: \.0.id) { snippet, rect in
                            SnippetButtonView(snippet: snippet, selected: selectedID == snippet.id, size: rect.size) {
                                select(snippet.id)
                            }
                            .contextMenu { actions(snippet.id) }
                            .position(x: rect.midX, y: rect.midY)
                        }
                        if let selectedID {
                            Button(role: .destructive) {
                                requestDeletion(selectedID)
                            } label: {
                                Label("删除", systemImage: "trash")
                                    .font(.system(size: 11)).frame(width: 60, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(.red)
                            .help("删除选中的文案")
                            .accessibilityLabel("删除选中的环形文案")
                            .position(x: layout.deletionRect.midX, y: layout.deletionRect.midY)
                        }
                    }
                    .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                }
                .defaultScrollAnchor(.center)
            }
        }
    }
}
