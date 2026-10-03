import KeyboardShortcuts
import SwiftUI

struct TriggerPreferencesCardView: View {
    @Bindable var viewModel: PreferencesViewModel
    var body: some View {
        SettingsCardView(title: "触发方式", symbol: "cursorarrow.click", badge: "主要设置") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsControlRow("启用快捷栏") {
                    Toggle(
                        "启用快捷栏",
                        isOn: Binding(
                            get: { viewModel.enabled },
                            set: { viewModel.enabled = $0 })
                    )
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(!viewModel.isReady)
                }
                Divider()
                SettingsControlRow("修饰键") {
                    Picker(
                        "修饰键",
                        selection: Binding(
                            get: { viewModel.clickModifier },
                            set: { viewModel.clickModifier = $0 })
                    ) {
                        Text("Option ⌥").tag(ClickModifier.option)
                        Text("Command ⌘").tag(ClickModifier.command)
                        Text("Shift ⇧").tag(ClickModifier.shift)
                    }
                    .labelsHidden().disabled(!viewModel.isReady)
                }
                SettingsControlRow("展开位置") {
                    Picker(
                        "展开位置",
                        selection: Binding(
                            get: { viewModel.menuAnchorMode },
                            set: { viewModel.menuAnchorMode = $0 })
                    ) {
                        ForEach(MenuAnchorMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().disabled(!viewModel.isReady)
                }
                SettingsExplanationView(
                    text: viewModel.menuAnchorMode == .mouse
                        ? "先点入输入框，将鼠标放在其中。按住触发键展开，移到文案按钮，松开后粘贴；未选中则取消。"
                        : "先点入输入框。按住触发键从输入光标处展开，再移动鼠标选择文案，松开后粘贴。无法定位光标时改用鼠标位置。")
                SettingsControlRow("快捷键") {
                    KeyboardShortcuts.Recorder(for: .toggleFloatingInputBar)
                        .accessibilityLabel("按住展开的快捷键")
                }
                SettingsExplanationView(text: "每个应用使用修饰键还是快捷键，请在首页选择应用后设置。")
            }
        }
    }
}
