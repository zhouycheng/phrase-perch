import SwiftUI

struct GroupContentsView: View {
    @Bindable var viewModel: ProfileEditorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.groupPath.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        Button("全部内容") { viewModel.openGroup(nil) }
                        ForEach(viewModel.groupPath, id: \.self) { id in
                            Image(systemName: "chevron.right").font(.caption)
                            Button(viewModel.groupTitle(id)) { viewModel.openGroup(id) }
                        }
                    }.buttonStyle(.plain)
                }
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.nodes) { node in
                        HStack(spacing: 8) {
                            if node.kind == .group {
                                Button { viewModel.openGroup(node.id) } label: { Image(systemName: "folder") }
                                    .accessibilityLabel("打开分组 \(viewModel.groupTitle(node.id))")
                                    .padding(.leading, 10)
                                TextField("分组名称", text: Binding(get: { viewModel.groupTitle(node.id) },
                                    set: { viewModel.setGroupTitle($0, id: node.id) }))
                                    .textFieldStyle(.plain)
                            } else {
                                Button { viewModel.select(node.id) } label: {
                                    Label(viewModel.title(node.id), systemImage: "text.alignleft")
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .padding(.leading, 10)
                                        .contentShape(Rectangle())
                                }
                            }
                            Toggle("启用", isOn: Binding(get: { viewModel.isEnabled(node) },
                                set: { viewModel.setEnabled($0, node: node) })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            if node.kind == .group {
                                Button { viewModel.openGroup(node.id) } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .accessibilityLabel("打开分组 \(viewModel.groupTitle(node.id))")
                                .frame(width: 24, height: 24)
                            }
                            Menu {
                                Button("上移") { viewModel.reorder(node, by: -1) }
                                Button("下移") { viewModel.reorder(node, by: 1) }
                                Menu("移到") {
                                    if viewModel.currentGroup != nil { Button("根级") { viewModel.moveNode(node, to: nil) } }
                                    ForEach(viewModel.destinations(for: node)) { group in
                                        Button(viewModel.groupLabel(group.id)) { viewModel.moveNode(node, to: group.id) }
                                    }
                                }
                                if node.kind == .snippet {
                                    Button("复制文案") { viewModel.duplicate(node.id) }
                                }
                            } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .accessibilityLabel("更多操作")
                                .frame(width: 24, height: 24)
                            Button(role: .destructive) {
                                if node.kind == .group {
                                    viewModel.removeGroup(node.id)
                                } else {
                                    viewModel.requestDeletion(node.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .accessibilityLabel(node.kind == .group ? "移除分组，内容移回本级" : "删除文案")
                            .help(node.kind == .group ? "移除分组，内容移回本级" : "删除文案")
                            .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .padding(.trailing, 10)
                        .background(viewModel.session.selectedID == node.id ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if viewModel.nodes.isEmpty { Text("添加文案、附件或分组").foregroundStyle(.secondary).padding() }
                }
            }
            Text(viewModel.attachmentMessage ?? viewModel.hierarchyIssue ?? viewModel.saveStatus)
                .font(.caption)
                .foregroundStyle(viewModel.hierarchyIssue == nil && viewModel.attachmentMessage == nil ? Color.secondary : Color.orange)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
