import SwiftUI

struct SnippetToolbarView: View {
    let displayMode: DisplayMode
    let toggleModifier: () -> Void
    let toggleShortcut: () -> Void
    let addSnippet: () -> Void
    let addGroup: () -> Void
    var addAttachments: () -> Void = {}
    var importingAttachment = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            header(stacked: false)
            header(stacked: true)
        }
        .padding(16)
    }

    private func header(stacked: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                Text("快捷内容").font(.body)
                buttonLayout(stacked: stacked) {
                    headerButton("新建文案", symbol: "plus", action: addSnippet)
                    headerButton("添加附件", symbol: "paperclip", action: addAttachments).disabled(importingAttachment)
                    headerButton("新建分组", symbol: "folder.badge.plus", action: addGroup)
                }
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            EditorStyle.separator.frame(width: 1)
            VStack(alignment: .leading, spacing: 12) {
                Text("调出方式").font(.body)
                buttonLayout(stacked: stacked) {
                    triggerButton("按住修饰键", symbol: "option", enabled: displayMode != .shortcutOnly,
                        action: toggleModifier)
                    triggerButton("按下快捷键", symbol: "keyboard", enabled: displayMode != .modifierClick,
                        action: toggleShortcut)
                }
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func buttonLayout<Content: View>(stacked: Bool, @ViewBuilder content: () -> Content) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout { content() }
    }

    private func headerButton(_ title: String, symbol: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(width: 104, height: 28)
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .background(highlighted ? Color.accentColor : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func triggerButton(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        headerButton(title, symbol: symbol, highlighted: enabled, action: action)
            .accessibilityValue(enabled ? "已开启" : "已关闭")
            .help(enabled && displayMode != .both ? "至少保留一种调出方式" : title)
    }
}
