import SwiftUI

struct SnippetToolbarView: View {
    let displayMode: DisplayMode
    let toggleModifier: () -> Void
    let toggleShortcut: () -> Void
    let addSnippet: () -> Void
    let addGroup: () -> Void
    var addAttachments: () -> Void = {}
    var importingAttachment = false
    var batchViewModel: ProfileEditorViewModel?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            header(stacked: false).frame(minWidth: 449)
            header(stacked: true)
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("content-toolbar")
    }

    private func header(stacked: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                Text("快捷内容").font(.body)
                ViewThatFits(in: .horizontal) {
                    creationButtons(twoRows: false, short: false)
                    creationButtons(twoRows: true, short: false)
                    creationButtons(twoRows: true, short: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(idealWidth: stacked ? 104 : 216, maxWidth: .infinity, alignment: .leading)
            EditorStyle.separator.frame(width: 1)
            VStack(alignment: .leading, spacing: 12) {
                Text("调出方式").font(.body)
                let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    triggerButton("按住修饰键", symbol: "option", enabled: displayMode != .shortcutOnly,
                        action: toggleModifier)
                    triggerButton("按下快捷键", symbol: "keyboard", enabled: displayMode != .modifierClick,
                        action: toggleShortcut)
                }
                .fixedSize().frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(idealWidth: stacked ? 104 : 216, maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func creationButtons(twoRows: Bool, short: Bool) -> some View {
        ContentToolbarButtonLayout(columns: twoRows ? 2 : 4) {
            creationButton("新建文案", short: short ? "文案" : "新建文案", symbol: "plus", action: addSnippet)
            creationButton("添加附件", short: short ? "附件" : "添加附件", symbol: "paperclip", action: addAttachments)
                .disabled(importingAttachment)
            creationButton("新建分组", short: short ? "分组" : "新建分组", symbol: "folder.badge.plus", action: addGroup)
            batchButton
        }
    }

    private var batchButton: some View {
        Menu {
            if let model = batchViewModel {
                destinationMenu("移动到", model: model, copying: false)
                destinationMenu("复制到", model: model, copying: true)
                Divider()
                Button("删除", role: .destructive) { model.requestBatchDeletion() }
            }
        } label: { creationLabel("操作", symbol: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .opacity(batchViewModel?.isBatchSelecting == true ? 1 : 0)
            .allowsHitTesting(batchViewModel?.isBatchSelecting == true)
            .disabled(batchViewModel?.isBatchSelecting != true)
            .accessibilityHidden(batchViewModel?.isBatchSelecting != true)
            .accessibilityLabel("批量操作").help("操作已选的 \(batchViewModel?.selectedNodeIDs.count ?? 0) 项")
    }

    private func destinationMenu(_ title: String, model: ProfileEditorViewModel, copying: Bool) -> some View {
        Menu(title) {
            ForEach(model.batchProfiles) { profile in
                Menu(profile.displayName) {
                    BatchDestinationMenu(viewModel: model, profile: profile, group: nil, copying: copying)
                }
            }
        }
    }

    private func creationButton(_ fullTitle: String, short: String, symbol: String,
        action: @escaping () -> Void) -> some View {
        Button(action: action) { creationLabel(short, symbol: symbol) }
            .buttonStyle(.plain).accessibilityLabel(fullTitle).help(fullTitle)
    }
    private func creationLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).frame(width: 16)
            Text(title).fixedSize()
        }
        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    private func triggerButton(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium)).frame(width: 104, height: 28)
            .foregroundStyle(enabled ? Color.white : Color.primary)
            .background(enabled ? Color.accentColor : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(enabled ? "已开启" : "已关闭")
        .help(enabled && displayMode != .both ? "至少保留一种调出方式" : title)
    }
}
