import SwiftUI

struct ProfileWorkspaceView: View {
    @Bindable var viewModel: MainWindowViewModel
    var body: some View {
        GeometryReader { geometry in
            let columns = EditorColumns(width: geometry.size.width + EditorColumns.navigation + 1)
            HStack(spacing: 0) {
                ApplicationListView(viewModel: viewModel).frame(width: columns.sidebar)
                EditorStyle.separator.frame(width: 1)
                if !viewModel.isReady {
                    EmptyStateView(
                        title: viewModel.loadIssue == nil ? "正在加载配置…" : "配置暂未加载，查看详情",
                        symbol: "externaldrive",
                        action: viewModel.loadIssue == nil ? nil : { viewModel.openConfiguration() })
                } else if let editor = viewModel.selectedEditor {
                    ProfileEditorView(viewModel: editor, editorWidth: columns.editor).id(editor.profileID)
                } else {
                    EmptyStateView(title: "添加应用", symbol: "app.badge", action: viewModel.chooseApplications)
                }
            }
        }
    }
}
