import AppKit
import SwiftUI

struct GroupContentsView: View {
    @Bindable var viewModel: ProfileEditorViewModel
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var contentOrigin = CGPoint.zero
    @State private var lastPointer: CGPoint?
    @State private var marqueeAdditive = false
    @State private var cancelledDrag = false
    @FocusState private var listFocused: Bool

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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.nodes) { node in
                                ContentListRow(viewModel: viewModel, node: node,
                                    reorderChanged: { value in
                                        guard !cancelledDrag else { return }
                                        viewModel.beginReordering(node.id)
                                        lastPointer = value.location
                                        updateGesture()
                                    }, reorderEnded: { value in
                                        if !cancelledDrag {
                                            viewModel.finishListGesture(inside: CGRect(origin: .zero, size: viewport.size).contains(value.location))
                                        }
                                        endPointerTracking()
                                    })
                                    .id(node.id)
                                    .background(GeometryReader { row in
                                        Color.clear.preference(key: ContentListGeometry.self,
                                            value: ContentListGeometry(frames: [node.id: row.frame(in: .named("contentRows"))]))
                                    })
                            }
                            if viewModel.nodes.isEmpty {
                                Text("添加文案、附件或分组").foregroundStyle(.secondary).padding().allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: viewport.size.height, alignment: .top)
                        .background {
                            Color.clear.contentShape(Rectangle()).onTapGesture {
                                viewModel.clearBatchSelection()
                                listFocused = true
                            }
                        }
                        .background(GeometryReader { content in
                            Color.clear.preference(key: ContentListGeometry.self,
                                value: ContentListGeometry(origin: content.frame(in: .named("contentViewport")).origin))
                        })
                        .overlay(alignment: .topLeading) {
                            if let rectangle = viewModel.marqueeRect {
                                Rectangle().fill(Color.accentColor.opacity(0.12))
                                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                                    .frame(width: rectangle.width, height: rectangle.height)
                                    .position(x: rectangle.midX, y: rectangle.midY).allowsHitTesting(false)
                            }
                            if !viewModel.draggingNodeIDs.isEmpty, viewModel.insertionBeforeID == nil,
                                let last = viewModel.nodes.last, let frame = rowFrames[last.id] {
                                Color.accentColor.frame(height: 2).offset(y: frame.maxY + 3).allowsHitTesting(false)
                            }
                        }
                        .coordinateSpace(name: "contentRows")
                    }
                    .coordinateSpace(name: "contentViewport")
                    .simultaneousGesture(marqueeGesture(in: CGRect(origin: .zero, size: viewport.size)))
                    .onPreferenceChange(ContentListGeometry.self) { geometry in
                        rowFrames.merge(geometry.frames) { _, new in new }
                        rowFrames = rowFrames.filter { id, _ in viewModel.nodes.contains { $0.id == id } }
                        if let origin = geometry.origin { contentOrigin = origin }
                        updateGesture()
                    }
                    .task(id: viewModel.isListGestureActive) {
                        while viewModel.isListGestureActive && !Task.isCancelled {
                            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                            autoScroll(proxy, size: viewport.size)
                        }
                    }
                }
            }
            Text(viewModel.batchIssue ?? viewModel.attachmentMessage ?? viewModel.hierarchyIssue
                ?? (viewModel.isImportingAttachment ? "正在添加附件…" : viewModel.isBatchSelecting
                    ? "已选 \(viewModel.selectedNodeIDs.count) 项 · \(viewModel.saveStatus)" : viewModel.saveStatus))
                .font(.caption)
                .foregroundStyle(viewModel.batchIssue == nil && viewModel.hierarchyIssue == nil ? Color.secondary : Color.orange)
                .lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .focusable().focused($listFocused).focusEffectDisabled()
        .onExitCommand {
            cancelledDrag = viewModel.isListGestureActive
            viewModel.clearBatchSelection()
            lastPointer = nil
        }
        .onChange(of: viewModel.nodes.map(\.id)) { _, _ in
            if lastPointer != nil {
                cancelledDrag = true
                viewModel.cancelListGesture()
                lastPointer = nil
            }
        }
        .onDisappear { viewModel.cancelListGesture(); endPointerTracking() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if viewModel.isListGestureActive { cancelledDrag = true; viewModel.cancelListGesture(); lastPointer = nil }
        }
        .alert("删除所选内容？", isPresented: Binding(get: { viewModel.batchDeletionIDs != nil },
            set: { if !$0 { viewModel.cancelBatchDeletion() } })) {
            Button("取消", role: .cancel) { viewModel.cancelBatchDeletion() }
            Button("删除", role: .destructive) { viewModel.confirmBatchDeletion() }
        } message: { Text(viewModel.batchDeletionMessage) }
    }

    private func marqueeGesture(in viewport: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("contentViewport"))
            .onChanged { value in
                guard !cancelledDrag, viewModel.draggingNodeIDs.isEmpty else { return }
                if viewModel.marqueeRect == nil {
                    let start = contentPoint(value.startLocation)
                    guard !rowFrames.values.contains(where: { $0.contains(start) }) else { return }
                    marqueeAdditive = NSEvent.modifierFlags.contains(.command)
                    viewModel.beginMarquee(at: start, additive: marqueeAdditive)
                    listFocused = true
                }
                lastPointer = value.location
                updateGesture()
            }
            .onEnded { value in
                if viewModel.isListGestureActive { viewModel.finishListGesture(inside: viewport.contains(value.location)) }
                endPointerTracking()
            }
    }
    private func contentPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - contentOrigin.x, y: point.y - contentOrigin.y)
    }
    private func updateGesture() {
        guard let pointer = lastPointer else { return }
        if viewModel.marqueeRect != nil {
            viewModel.updateMarquee(to: contentPoint(pointer), frames: rowFrames, additive: marqueeAdditive)
        } else if !viewModel.draggingNodeIDs.isEmpty {
            viewModel.updateInsertion(at: contentPoint(pointer), frames: rowFrames)
        }
    }
    private func endPointerTracking() { lastPointer = nil; cancelledDrag = false }
    private func autoScroll(_ proxy: ScrollViewProxy, size: CGSize) {
        guard viewModel.isListGestureActive, let pointer = lastPointer,
            pointer.x >= 0, pointer.x <= size.width, pointer.y >= 0, pointer.y <= size.height else { return }
        let visible = viewModel.nodes.enumerated().filter { _, node in
            rowFrames[node.id].map { $0.maxY + contentOrigin.y > 0 && $0.minY + contentOrigin.y < size.height } == true
        }
        if pointer.y < 24, let first = visible.first, first.offset > 0 {
            proxy.scrollTo(viewModel.nodes[first.offset - 1].id, anchor: .top)
        } else if pointer.y > size.height - 24, let last = visible.last, last.offset + 1 < viewModel.nodes.count {
            proxy.scrollTo(viewModel.nodes[last.offset + 1].id, anchor: .bottom)
        }
    }
}

private struct ContentListGeometry: PreferenceKey, Equatable {
    var frames: [UUID: CGRect] = [:]
    var origin: CGPoint?
    static let defaultValue = ContentListGeometry()
    static func reduce(value: inout ContentListGeometry, nextValue: () -> ContentListGeometry) {
        let next = nextValue()
        value.frames.merge(next.frames) { _, new in new }
        if let origin = next.origin { value.origin = origin }
    }
}
