import SwiftUI

struct SnippetDetailView: View {
    @Bindable var viewModel: ProfileEditorViewModel

    var body: some View {
        Group {
            if let source = viewModel.selectedSyncSource, let syncID = viewModel.selectedSyncID {
                VStack(alignment: .leading, spacing: 16) {
                    Label(source.displayName, systemImage: "folder.badge.gearshape").font(.title2)
                    Text("同步引入此应用中的全部内容，包含分组、附件及多级同步。来源内容变化后自动更新。")
                        .foregroundStyle(.secondary)
                    Text("双击同步入口前往来源应用编辑。")
                        .foregroundStyle(.secondary)
                    Button("前往来源应用") { viewModel.openSyncSource(syncID) }
                    Spacer()
                }.padding(EditorStyle.contentInset)
            } else if let snippet = viewModel.selectedSnippet {
                VStack(alignment: .leading, spacing: 16) {
                    SnippetTitleEditorView(
                        text: Binding(
                            get: { viewModel.title(snippet.id) }, set: { viewModel.setTitle($0, id: snippet.id) }),
                        issue: viewModel.titleIssue)
                    Color.white.opacity(0.08).frame(height: 1)
                    if let file = snippet.attachment {
                        AttachmentEditorView(viewModel: viewModel, file: file)
                    } else { SnippetBodyEditorView(
                        text: Binding(
                            get: { viewModel.text(snippet.id) }, set: { viewModel.setText($0, id: snippet.id) }),
                        issue: viewModel.textIssue) }
                    SnippetSaveStatusView(viewModel: viewModel, snippet: snippet)
                }
                .padding(EditorStyle.contentInset)
                .id(snippet.id)
            } else {
                EmptyStateView(title: "选择内容开始编辑", symbol: "text.alignleft")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
