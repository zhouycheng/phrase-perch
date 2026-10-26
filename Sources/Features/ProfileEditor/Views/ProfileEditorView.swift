import SwiftUI

struct ProfileEditorView: View {
    @Bindable var viewModel: ProfileEditorViewModel
    let editorWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                SnippetToolbarView(
                    displayMode: viewModel.displayMode,
                    toggleModifier: viewModel.toggleModifierTrigger, toggleShortcut: viewModel.toggleShortcutTrigger,
                    addSnippet: viewModel.addSnippet, addGroup: viewModel.addGroup,
                    addAttachments: viewModel.addAttachments, importingAttachment: viewModel.isImportingAttachment)
                GroupContentsView(viewModel: viewModel)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            EditorStyle.separator.frame(width: 1)
            Group {
                if let snippet = viewModel.selectedSnippet {
                    VStack(alignment: .leading, spacing: 16) {
                        SnippetTitleEditorView(
                            text: Binding(
                                get: { viewModel.title(snippet.id) }, set: { viewModel.setTitle($0, id: snippet.id) }),
                            issue: viewModel.titleIssue)
                        Color.white.opacity(0.08).frame(height: 1)
                        if let file = snippet.attachment {
                            AttachmentEditorView(viewModel: viewModel, file: file)
                        } else {
                            SnippetBodyEditorView(
                                text: Binding(
                                    get: { viewModel.text(snippet.id) }, set: { viewModel.setText($0, id: snippet.id) }),
                                issue: viewModel.textIssue)
                        }
                        SnippetSaveStatusView(viewModel: viewModel, snippet: snippet)
                    }
                    .padding(EditorStyle.contentInset)
                    .id(snippet.id)
                } else {
                    EmptyStateView(title: "选择内容开始编辑", symbol: "text.alignleft")
                }
            }
            .frame(width: editorWidth)
            .frame(maxHeight: .infinity)
        }
        .alert(
            "删除这条内容？",
            isPresented: Binding(
                get: { viewModel.deletionID != nil },
                set: { if !$0 { viewModel.cancelDeletion() } }), presenting: viewModel.deletionID
        ) { id in
            Button("取消", role: .cancel) { viewModel.cancelDeletion() }
            Button("删除", role: .destructive) {
                viewModel.confirmDeletion(id)
            }
        } message: { id in
            Text(viewModel.title(id))
        }

    }

}
