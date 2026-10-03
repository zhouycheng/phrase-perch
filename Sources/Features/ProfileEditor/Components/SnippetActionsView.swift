import SwiftUI

struct SnippetActionsView: View {
    let viewModel: ProfileEditorViewModel
    let id: UUID
    var body: some View {
        Button("复制文案") { viewModel.duplicate(id) }
        Button("上移") { viewModel.move(id, by: -1) }.disabled(viewModel.ids.first == id)
        Button("下移") { viewModel.move(id, by: 1) }.disabled(viewModel.ids.last == id)
        Divider()
        Button("删除文案…", role: .destructive) { viewModel.requestDeletion(id) }
    }
}
