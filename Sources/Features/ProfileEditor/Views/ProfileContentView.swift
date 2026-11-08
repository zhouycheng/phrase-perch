import SwiftUI

struct ProfileContentView: View {
    @Bindable var viewModel: ProfileEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            SnippetToolbarView(
                displayMode: viewModel.displayMode,
                toggleModifier: viewModel.toggleModifierTrigger, toggleShortcut: viewModel.toggleShortcutTrigger,
                addSnippet: viewModel.addSnippet, addGroup: viewModel.addGroup,
                addAttachments: viewModel.addAttachments, importingAttachment: viewModel.isImportingAttachment,
                batchViewModel: viewModel)
            GroupContentsView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
