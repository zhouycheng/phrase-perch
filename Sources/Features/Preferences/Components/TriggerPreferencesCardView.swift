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
                Toggle("文案使用剪贴板粘贴", isOn: $viewModel.copyOnInsert)
                    .disabled(!viewModel.isReady)
                SettingsExplanationView(text: "关闭后文案通过辅助功能直接写入；附件始终使用剪贴板。空白区域选中内容时复制到剪贴板。")
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
                        ? "输入框中选中内容后粘贴，空白区域选中后复制。修饰键按住展开、移动选择、松开提交；组合快捷键按一次打开轮盘，点击内容提交。菜单在鼠标附近显示。"
                        : "菜单优先在输入光标附近展开；光标不可用时在输入框可见区域或鼠标附近显示。")
                SettingsControlRow("快捷键") {
                    KeyboardShortcuts.Recorder(for: .togglePhrasePerch)
                        .accessibilityLabel("按一次打开快捷轮盘的快捷键")
                }
                SettingsExplanationView(text: viewModel.shortcutStatus)
                SettingsExplanationView(text: "在首页点亮应用的调出方式。悬停高亮的“下一页”展开更多内容，悬停“上一页”恢复上一张轮盘。")
            }
        }
    }
}
