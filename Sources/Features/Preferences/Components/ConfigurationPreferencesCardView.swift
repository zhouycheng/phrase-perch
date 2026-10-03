import SwiftUI

struct ConfigurationPreferencesCardView: View {
    @Bindable var viewModel: PreferencesViewModel
    let requestRecovery: () -> Void
    var body: some View {
        SettingsCardView(title: "配置", symbol: "externaldrive", badge: "按需使用") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button("导入配置…", action: viewModel.importConfiguration)
                    Button("导出配置…", action: viewModel.exportConfiguration)
                        .disabled(!viewModel.isReady)
                    Spacer()
                    SettingsExplanationView(text: "配置保存在本机")
                }
                if let issue = viewModel.issue {
                    Divider()
                    Text(issue.operation.rawValue).font(.callout.weight(.medium))
                    Text(issue.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let message = viewModel.validationMessage {
                    SettingsExplanationView(text: "待补全文案：\(message)。补齐后会自动保存。")
                }
                HStack(spacing: 10) {
                    if !viewModel.isReady, viewModel.issue != nil {
                        Button("重新读取") { viewModel.retryLoad() }
                    }
                    if viewModel.issue?.operation == .save {
                        Button("重试保存") { viewModel.retrySave() }
                    }
                    Button("恢复最近备份…", action: requestRecovery)
                }
            }
        }
    }
}
