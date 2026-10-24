import SwiftUI

struct PreferencesView: View {
    @Bindable var viewModel: PreferencesViewModel
    let requestRecovery: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeaderView(title: "设置", subtitle: "管理快捷栏、系统权限和启动方式")

                TriggerPreferencesCardView(viewModel: viewModel)

                SettingsCardView(title: "最近交互", symbol: "clock", badge: "本次运行") {
                    VStack(alignment: .leading, spacing: 10) {
                        if viewModel.diagnostics.entries.isEmpty { Text("触发文案菜单后，这里显示耗时和结果。").foregroundStyle(.secondary) }
                        ForEach(viewModel.diagnostics.entries) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(entry.stage) · \(Int(entry.elapsed * 1000)) ms · \(entry.anchor)")
                                if let ready = entry.readyAfter {
                                    Text("展开耗时 \(Int(ready * 1000)) ms").font(.caption).foregroundStyle(.secondary)
                                }
                                if !entry.detail.isEmpty { Text(entry.detail).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }

                AuthorizationPreferencesCardView(viewModel: viewModel)

                AppEntryPreferencesCardView(viewModel: viewModel)

                ConfigurationPreferencesCardView(viewModel: viewModel, requestRecovery: requestRecovery)
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
