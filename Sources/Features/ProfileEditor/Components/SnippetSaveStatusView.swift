import SwiftUI

struct SnippetSaveStatusView: View {
    @Bindable var viewModel: ProfileEditorViewModel
    let snippet: Snippet
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if viewModel.saveStatus == "保存失败", let configurationIssue = viewModel.configurationIssue {
                Button(viewModel.saveStatus) { viewModel.showSaveIssue = true }
                    .buttonStyle(.plain).help("查看保存详情")
                    .popover(isPresented: $viewModel.showSaveIssue) {
                        SaveIssueDetailView(
                            message: configurationIssue.message, retry: viewModel.retrySave,
                            openConfiguration: viewModel.openConfiguration)
                    }
            } else {
                Text(viewModel.saveStatus)
            }
            Spacer(minLength: 4)
            Text("\(snippet.text.utf8.count) B / 64 KiB").monospacedDigit()
            Button(role: .destructive) {
                viewModel.requestDeletion(snippet.id)
            } label: {
                Image(systemName: "trash").frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.red)
            .help("删除文案 \(snippet.title)")
            .accessibilityLabel("删除当前编辑文案")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
