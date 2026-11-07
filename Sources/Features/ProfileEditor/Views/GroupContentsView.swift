import AppKit
import SwiftUI

struct GroupContentsView: View {
    @Bindable var viewModel: ProfileEditorViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentOrigin = CGPoint.zero
    @State private var lastPointer: CGPoint?
    @State private var draggedNode: MenuNode?
    @State private var landing = false
    @State private var grabOffset = CGPoint.zero
    @State private var reorderWidth: CGFloat = 0
    @State private var marqueeAdditive = false
    @State private var isDropTargeted = false
    @FocusState private var listFocused: Bool

    private var showsInsertion: Bool { !viewModel.draggingNodeIDs.isEmpty && viewModel.reorderHasMoved }
    private var listAnimation: Animation? { reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86) }

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
            GeometryReader { viewport in
                let rowWidth = max(0, viewport.size.width - ContentListLayout.avoidanceOutset)
                let avoidance = avoidanceDistances()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.nodes) { node in
                                VStack(alignment: .leading, spacing: 0) {
                                    if !viewModel.draggingNodeIDs.contains(node.id) {
                                        if let label = viewModel.pagePreview.markers[node.id] { pageHeader(label) }
                                        ContentListRow(viewModel: viewModel, node: node)
                                            .frame(width: rowWidth)
                                            .opacity(landing && draggedNode?.id == node.id ? 0 : 1)
                                            .offset(x: avoidance[node.id].map { ContentListLayout.avoidance(distance: $0) } ?? 0)
                                            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)
                                                .delay(Double(avoidance[node.id] ?? 0) * 0.024), value: avoidance[node.id])
                                            .padding(.bottom, ContentListLayout.spacing)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(node.id)
                                .transition(.opacity)
                            }
                            if viewModel.nodes.isEmpty {
                                Text("添加文案、附件、分组或同步，也可拖入文件")
                                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding().allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: viewport.size.height, alignment: .top)
                        .onGeometryChange(for: CGPoint.self) { content in
                            content.frame(in: .named("contentViewport")).origin
                        } action: { origin in
                            contentOrigin = origin
                            updateGesture(width: rowWidth)
                        }
                        .overlay(alignment: .topLeading) {
                            if let rectangle = viewModel.marqueeRect {
                                Rectangle().fill(Color.accentColor.opacity(0.12))
                                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                                    .frame(width: rectangle.width, height: rectangle.height)
                                    .position(x: rectangle.midX, y: rectangle.midY).allowsHitTesting(false)
                            }
                        }
                        .animation(listAnimation, value: viewModel.draggingNodeIDs)
                    }
                    .coordinateSpace(name: "contentViewport")
                    .background(interaction(size: viewport.size))
                    .onPreferenceChange(ContentListRow.ReorderWidthKey.self) { reorderWidth = $0 }
                    .overlay(alignment: .topLeading) { floatingRow(width: rowWidth) }
                    .task(id: viewModel.isListGestureActive) {
                        while viewModel.isListGestureActive && !Task.isCancelled {
                            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                            autoScroll(proxy, size: viewport.size)
                        }
                    }
                    .task(id: landing) {
                        guard landing else { return }
                        do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
                        endPointerTracking()
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in viewModel.addAttachments(from: urls) }
                isTargeted: { isDropTargeted = $0 }
            .overlay {
                if isDropTargeted && !viewModel.isImportingAttachment {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 2))
                        .allowsHitTesting(false)
                }
            }
            .help("长按 0.6 秒拖动排序；将文件拖到列表添加附件")
            Text(viewModel.batchIssue ?? viewModel.attachmentMessage ?? viewModel.hierarchyIssue ?? viewModel.pagePreview.issue
                ?? (viewModel.isImportingAttachment ? "正在添加附件…" : viewModel.isBatchSelecting
                    ? "已选 \(viewModel.selectedNodeIDs.count) 项 · \(viewModel.saveStatus)" : viewModel.saveStatus))
                .font(.caption)
                .foregroundStyle(viewModel.batchIssue == nil && viewModel.hierarchyIssue == nil && viewModel.pagePreview.issue == nil
                    ? Color.secondary : Color.orange)
                .lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .focusable().focused($listFocused).focusEffectDisabled()
        .onExitCommand { viewModel.clearBatchSelection(); endPointerTracking() }
        .onChange(of: viewModel.isListGestureActive) { _, active in if !active && !landing { endPointerTracking() } }
        .onDisappear { viewModel.cancelListGesture(); endPointerTracking() }
        .alert("删除所选内容？", isPresented: Binding(get: { viewModel.batchDeletionIDs != nil },
            set: { if !$0 { viewModel.cancelBatchDeletion() } })) {
            Button("取消", role: .cancel) { viewModel.cancelBatchDeletion() }
            Button("删除", role: .destructive) { viewModel.confirmBatchDeletion() }
        } message: { Text(viewModel.batchDeletionMessage) }
    }

    private func pageHeader(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).fixedSize()
            Rectangle().frame(height: 1).opacity(0.35)
        }
        .foregroundStyle(.secondary).frame(height: ContentListLayout.pageHeaderHeight)
        .allowsHitTesting(false).accessibilityAddTraits(.isHeader)
    }
    @ViewBuilder private func floatingRow(width: CGFloat) -> some View {
        if let node = draggedNode, let pointer = lastPointer, !viewModel.draggingNodeIDs.isEmpty || landing {
            ContentListRow(viewModel: viewModel, node: node, isFloating: true)
                .frame(width: width)
                .background(EditorStyle.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if viewModel.draggingNodeIDs.count > 1 && !landing {
                        Text("\(viewModel.draggingNodeIDs.count) 项").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule()).offset(x: -8, y: -10)
                    }
                }
                .scaleEffect(reduceMotion || landing ? 1 : 1.025,
                    anchor: UnitPoint(x: grabOffset.x / max(1, width), y: grabOffset.y / ContentListLayout.rowHeight))
                .shadow(color: .black.opacity(landing ? 0 : 0.3), radius: landing ? 0 : 12, y: landing ? 0 : 6)
                .position(x: pointer.x - grabOffset.x + width / 2,
                    y: pointer.y - grabOffset.y + ContentListLayout.rowHeight / 2)
                .transaction { if !landing { $0.animation = nil } }
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    private func layout(width: CGFloat) -> ContentListLayout {
        ContentListLayout(nodes: viewModel.nodes, markers: viewModel.pagePreview.markers,
            width: width, excluding: viewModel.draggingNodeIDs)
    }
    private func interaction(size: CGSize) -> ContentListInteraction {
        let width = max(0, size.width - ContentListLayout.avoidanceOutset)
        return ContentListInteraction(prepare: {
            if landing { endPointerTracking() }
            viewModel.prepareListPress()
        }, rowAt: { point in
            guard point.x <= reorderWidth else { return nil }
            let point = contentPoint(point), rows = layout(width: width)
            return rows.nodes.first { rows.frames[$0.id]?.contains(point) == true }?.id
        }, isBlank: { point in
            let point = contentPoint(point), rows = layout(width: width)
            return !rows.nodes.contains { node in
                guard let frame = rows.frames[node.id] else { return false }
                let header = viewModel.pagePreview.markers[node.id] == nil ? 0 : ContentListLayout.pageHeaderHeight
                return CGRect(x: frame.minX, y: frame.minY - header, width: frame.width, height: frame.height + header).contains(point)
            }
        }, lift: { id, point in
            guard let node = viewModel.nodes.first(where: { $0.id == id }),
                let frame = layout(width: width).frames[id] else { return }
            grabOffset = CGPoint(x: point.x - frame.minX - contentOrigin.x, y: point.y - frame.minY - contentOrigin.y)
            lastPointer = point; draggedNode = node
            viewModel.beginReordering(id)
            listFocused = true
        }, beginMarquee: { point, additive in
            marqueeAdditive = additive
            viewModel.beginMarquee(at: contentPoint(point), additive: additive)
            listFocused = true
        }, move: { point, moved in
            lastPointer = point
            if moved { updateGesture(width: width, moved: true) }
        }, finish: { point in
            landing = draggedNode != nil && !reduceMotion
            viewModel.finishListGesture(inside: CGRect(origin: .zero, size: size).contains(point))
            if landing, let id = draggedNode?.id, let frame = layout(width: width).frames[id] {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    lastPointer = CGPoint(x: grabOffset.x, y: frame.minY + contentOrigin.y + grabOffset.y)
                }
            } else { endPointerTracking() }
        }, cancel: {
            viewModel.cancelListGesture(); endPointerTracking()
        }, clickBlank: {
            viewModel.clearBatchSelection(); listFocused = true
        }, isActive: { viewModel.isListGestureActive }, screenChanged: viewModel.setPreviewScreen)
    }
    private func contentPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - contentOrigin.x, y: point.y - contentOrigin.y)
    }
    private func updateGesture(width: CGFloat, moved: Bool = false) {
        guard let pointer = lastPointer else { return }
        let frames = layout(width: width).frames
        if viewModel.marqueeRect != nil {
            viewModel.updateMarquee(to: contentPoint(pointer), frames: frames, additive: marqueeAdditive)
        } else if !viewModel.draggingNodeIDs.isEmpty && (moved || viewModel.reorderHasMoved) {
            viewModel.updateInsertion(at: contentPoint(pointer), frames: frames)
        }
    }
    private func avoidanceDistances() -> [UUID: Int] {
        guard showsInsertion else { return [:] }
        let nodes = viewModel.nodes.filter { !viewModel.draggingNodeIDs.contains($0.id) }
        let target = nodes.firstIndex { $0.id == viewModel.insertionBeforeID } ?? nodes.count
        return Dictionary(uniqueKeysWithValues: nodes.enumerated().compactMap { index, node in
            let distance = index < target ? target - index - 1 : index - target
            return distance <= 4 ? (node.id, distance) : nil
        })
    }
    private func endPointerTracking() { lastPointer = nil; draggedNode = nil; landing = false }
    private func autoScroll(_ proxy: ScrollViewProxy, size: CGSize) {
        guard viewModel.isListGestureActive, let pointer = lastPointer,
            CGRect(origin: .zero, size: size).contains(pointer) else { return }
        let rows = layout(width: max(0, size.width - ContentListLayout.avoidanceOutset))
        let visible = rows.nodes.enumerated().filter { _, node in
            guard let frame = rows.frames[node.id] else { return false }
            return frame.maxY + contentOrigin.y > 0 && frame.minY + contentOrigin.y < size.height
        }
        if pointer.y < 24, let first = visible.first, first.offset > 0 {
            proxy.scrollTo(rows.nodes[first.offset - 1].id, anchor: .top)
        } else if pointer.y > size.height - 24, let last = visible.last, last.offset + 1 < rows.nodes.count {
            proxy.scrollTo(rows.nodes[last.offset + 1].id, anchor: .bottom)
        }
    }
}
