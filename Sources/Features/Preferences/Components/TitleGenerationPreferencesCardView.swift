import SwiftUI

struct TitleGenerationPreferencesCardView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        SettingsCardView(title: "AI 标题", symbol: "text.badge.star", badge: "CLIProxyAPI") {
            VStack(alignment: .leading, spacing: 14) {
                SettingsControlRow("服务地址") {
                    TextField(Preferences.defaultTitleAPIBaseURL, text: $viewModel.titleAPIBaseURL)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("标题生成服务地址")
                }
                SettingsControlRow("标题模型") {
                    Picker("标题模型", selection: $viewModel.titleModel) {
                        Text("请选择模型").tag("")
                        if !viewModel.titleModel.isEmpty, !viewModel.titleModels.contains(viewModel.titleModel) {
                            Text(viewModel.titleModel).tag(viewModel.titleModel)
                        }
                        ForEach(viewModel.titleModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().accessibilityLabel("标题生成模型")
                }
                HStack(spacing: 10) {
                    Button(viewModel.isReadingModels ? "读取中…" : "读取模型", action: viewModel.readTitleModels)
                        .disabled(viewModel.isReadingModels)
                    if viewModel.isReadingModels { ProgressView().controlSize(.small) }
                    Button(viewModel.isSavingTitleSettings ? "保存中…" : "保存设置") {
                        Task { await viewModel.saveTitleSettings() }
                    }
                }
                SettingsExplanationView(text: "连接本机运行的 CLIProxyAPI。在编辑区点击“生成标题”后，正文会由本地服务转发至所选模型。")
                if let message = viewModel.titleSettingsMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .disabled(!viewModel.isReady || viewModel.isSavingTitleSettings)
        }
        .task(id: viewModel.isReady) { viewModel.loadTitleSettings() }
        .onDisappear { viewModel.cancelModelsRead() }
    }
}
