import SwiftUI

struct ProfileWorkspaceView: View {
    @Bindable var viewModel: MainWindowViewModel
    var layoutDefaults: UserDefaults? = .standard
    var body: some View {
        WorkspaceSplitView(sidebar: AnyView(ApplicationListView(viewModel: viewModel)),
            content: AnyView(content), detail: AnyView(detail), defaults: layoutDefaults)
    }

    @ViewBuilder private var content: some View {
        if !viewModel.isReady {
            EmptyStateView(title: viewModel.loadIssue == nil ? "正在加载配置…" : "配置暂未加载，查看详情",
                symbol: "externaldrive", action: viewModel.loadIssue == nil ? nil : { viewModel.openConfiguration() })
        } else if let editor = viewModel.selectedEditor {
            ProfileContentView(viewModel: editor).id(editor.profileID)
        } else {
            EmptyStateView(title: "添加应用", symbol: "app.badge", action: viewModel.chooseApplications)
        }
    }

    @ViewBuilder private var detail: some View {
        if viewModel.isReady, let editor = viewModel.selectedEditor {
            SnippetDetailView(viewModel: editor).id(editor.profileID)
        } else {
            EmptyStateView(title: "选择内容开始编辑", symbol: "text.alignleft")
        }
    }
}
