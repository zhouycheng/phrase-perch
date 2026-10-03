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
                Divider()
                SettingsControlRow("在 Dock 中显示图标") {
                    Toggle(
                        "在 Dock 中显示图标",
                        isOn: Binding(
                            get: { viewModel.dockIconVisible },
                            set: { viewModel.dockIconVisible = $0 })
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
            }
        }
    }
}
