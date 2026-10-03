import SwiftUI

struct SnippetPaginationView: View {
    let viewModel: ProfileEditorViewModel
    var body: some View {
        HStack(spacing: 14) {
            if viewModel.pages > 1 {
                Button {
                    viewModel.showPage(viewModel.session.page - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.session.page == 0).help("上一页").accessibilityLabel("上一页")
                Text("\(viewModel.session.page + 1) / \(viewModel.pages)").monospacedDigit()
                Button {
                    viewModel.showPage(viewModel.session.page + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.session.page == viewModel.pages - 1).help("下一页").accessibilityLabel("下一页")
            }
        }
        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        .frame(height: 56)
    }
}
