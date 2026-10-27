import SwiftUI

struct AppEntryPreferencesCardView: View {
    @Bindable var viewModel: PreferencesViewModel
    var body: some View {
        SettingsCardView(title: "启动与显示", symbol: "rectangle.on.rectangle", badge: "可选") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsControlRow("登录时启动") {
                    Toggle(
                        "登录时启动",
                        isOn: Binding(
                            get: { viewModel.loginEnabled },
                            set: { viewModel.loginEnabled = $0 })
                    )
                    .labelsHidden().toggleStyle(.switch)
                }
                SettingsControlRow("静默启动") {
                    Toggle("静默启动", isOn: $viewModel.silentLaunchEnabled)
                        .disabled(!viewModel.loginEnabled)
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingsExplanationView(text: "登录时在后台启动。手动打开应用时显示主窗口。")
                Divider()
                SettingsControlRow("后台运行时隐藏 Dock 图标") {
                    Toggle(
                        "后台运行时隐藏 Dock 图标",
                        isOn: Binding(
                            get: { !viewModel.dockIconVisible },
                            set: { viewModel.dockIconVisible = !$0 })
                    )
                    .disabled(!viewModel.menuBarIconVisible)
                    .labelsHidden().toggleStyle(.switch)
                }
                SettingsControlRow("在菜单栏显示图标") {
                    Toggle(
                        "在菜单栏显示图标",
                        isOn: Binding(
                            get: { viewModel.menuBarIconVisible },
                            set: { viewModel.menuBarIconVisible = $0 })
                    )
                    .disabled(!viewModel.dockIconVisible)
                    .labelsHidden().toggleStyle(.switch)
                }
                SettingsExplanationView(text: "请至少保留 Dock 或菜单栏中的一个入口。")
                SettingsExplanationView(text: "主窗口打开或最小化时始终显示 Dock 图标，关闭窗口后按此设置显示。")
                if !viewModel.entryNotice.isEmpty {
                    Text(viewModel.entryNotice).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}
