import SwiftUI

struct ContentListRow: View {
    @Bindable var viewModel: ProfileEditorViewModel
    let node: MenuNode
    let reorderChanged: (DragGesture.Value) -> Void
    let reorderEnded: (DragGesture.Value) -> Void
    @State private var hoveringIcon = false
    @State private var sorting = false
    @GestureState private var trackingSort = false

    private var title: String { viewModel.profile?.title(of: node) ?? "" }
    private var checked: Bool { viewModel.selectedNodeIDs.contains(node.id) }
    private var symbol: String {
        node.kind == .group ? "folder" : viewModel.isAttachment(node.id) ? "paperclip" : "text.alignleft"
    }
    private var reorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 6)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("contentViewport")))
            .updating($trackingSort) { value, tracking, _ in
                if case .second(true, _) = value { tracking = true }
            }
            .onChanged { value in
                if case .second(true, let drag?) = value,
                    abs(drag.translation.width) + abs(drag.translation.height) >= 3 {
                    sorting = true
                    reorderChanged(drag)
                }
            }
            .onEnded { value in
                if sorting, case .second(true, let drag?) = value { reorderEnded(drag) }
            }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { if !sorting { viewModel.toggleNodeSelection(node.id) } } label: {
                Image(systemName: hoveringIcon || viewModel.isBatchSelecting
                    ? (checked ? "checkmark.square.fill" : "square") : symbol)
                    .foregroundStyle(checked ? Color.accentColor : Color.primary)
                    .frame(width: 18, height: 44).padding(.leading, 10).contentShape(Rectangle())
            }
            .onHover { hoveringIcon = $0 }
            .accessibilityLabel("选择 \(title)").accessibilityValue(checked ? "已选择" : "未选择")
            .accessibilityRepresentation {
                Toggle("选择 \(title)", isOn: Binding(get: { checked },
                    set: { value in if value != checked { viewModel.toggleNodeSelection(node.id) } }))
                    .toggleStyle(.checkbox)
            }
            .help("选择内容；长按拖动排序").simultaneousGesture(reorderGesture)
            if node.kind == .group && !viewModel.isBatchSelecting {
                TextField("分组名称", text: Binding(get: { viewModel.groupTitle(node.id) },
                    set: { viewModel.setGroupTitle($0, id: node.id) }))
                    .textFieldStyle(.plain).accessibilityLabel("分组名称")
            } else {
                Button { if !sorting { viewModel.activateNode(node) } } label: {
                    Text(title).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .simultaneousGesture(reorderGesture)
            }
            Toggle("启用 \(title)", isOn: Binding(get: { viewModel.isEnabled(node) },
                set: { viewModel.setEnabled($0, node: node) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            if node.kind == .group {
                Button { viewModel.openGroup(node.id) } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("打开分组 \(title)").frame(width: 24, height: 24)
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
                    Button(viewModel.isAttachment(node.id) ? "复制附件" : "复制文案") { viewModel.duplicate(node.id) }
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .accessibilityLabel("更多操作").frame(width: 24, height: 24)
            Button(role: .destructive) {
                if node.kind == .group { viewModel.removeGroup(node.id) }
                else { viewModel.requestDeletion(node.id) }
            } label: { Image(systemName: "trash").foregroundStyle(.red) }
                .accessibilityLabel(node.kind == .group ? "移除分组，内容移回本级" : "删除内容")
                .help(node.kind == .group ? "移除分组，内容移回本级" : "删除内容").frame(width: 24, height: 24)
        }
        .buttonStyle(.plain).frame(height: 44).padding(.trailing, 10)
        .background(checked || (!viewModel.isBatchSelecting && viewModel.session.selectedID == node.id)
            ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(viewModel.draggingNodeIDs.contains(node.id) ? 0.55 : 1)
        .onChange(of: trackingSort) { _, tracking in
            if !tracking { DispatchQueue.main.async { sorting = false } }
        }
        .overlay(alignment: .top) {
            if !viewModel.draggingNodeIDs.isEmpty && viewModel.insertionBeforeID == node.id {
                Color.accentColor.frame(height: 2).offset(y: -4).allowsHitTesting(false)
            }
        }
    }
}
