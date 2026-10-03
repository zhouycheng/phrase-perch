import SwiftUI

struct ApplicationListView: View {
    @Bindable var viewModel: MainWindowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("应用列表").font(.system(size: 18, weight: .medium))
                .frame(height: EditorStyle.headerHeight)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.profiles) { profile in
                        ApplicationRowView(
                            profile: profile, selected: viewModel.selectedProfile == profile.id,
                            enabled: Binding(get: { profile.isEnabled }, set: { viewModel.setEnabled(profile.id, $0) }),
                            select: { viewModel.selectProfile(profile.id) },
                            requestDelete: { viewModel.requestDeletion(profile.id) })
                    }
                }
            }
            .disabled(!viewModel.isReady)
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 16) {
                Menu {
                    Button("选择 .app 文件…", action: viewModel.chooseApplications)
                    Menu("正在运行的应用") {
                        ForEach(viewModel.runningApplications) { app in
                            Button(app.name) { viewModel.addApplication(app.url) }
                        }
                    }
                } label: {
                    Label("添加应用", systemImage: "plus")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .disabled(!viewModel.isReady)

            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
