import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: MainWindowViewModel
    let preferences: PreferencesViewModel

    var body: some View {
        HStack(spacing: 0) {
            NavigationRailView(page: $viewModel.page)
            EditorStyle.separator.frame(width: 1)
            VStack(spacing: 0) {
                Group {
                    switch viewModel.page {
                    case .home:
                        ProfileWorkspaceView(viewModel: viewModel)
                    case .settings: PreferencesView(viewModel: preferences, requestRecovery: viewModel.requestRecovery)
                    case .about: AboutView(metadata: viewModel.applicationMetadata)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .background(EditorStyle.background)
        .preferredColorScheme(.dark)
        .disabled(viewModel.isRestarting)

        .alert(
            "移除应用及其全部文案？",
            isPresented: Binding(
                get: { viewModel.deleteProfile != nil }, set: { if !$0 { viewModel.cancelDeletion() } }),
            presenting: viewModel.deleteProfile
        ) { id in
            Button("取消", role: .cancel, action: viewModel.cancelDeletion)
            Button("移除", role: .destructive) { viewModel.confirmDeletion(id) }
        } message: { _ in
            Text(viewModel.deletionName)
        }
        .alert("从最近有效备份恢复？", isPresented: $viewModel.recoveryAlert) {
            Button("取消", role: .cancel) {}
            Button("恢复") { viewModel.recover() }
        } message: {
            Text("当前文件会保留，然后写入备份配置。")
        }
    }

}
