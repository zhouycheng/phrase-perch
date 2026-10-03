import SwiftUI
import AppKit
import KeyboardShortcuts

enum MainPage: CaseIterable {
    case home, settings, about
    var title: String {
        switch self { case .home: "首页"; case .settings: "设置"; case .about: "关于" }
    }
    var symbol: String {
        switch self { case .home: "house.fill"; case .settings: "gearshape.fill"; case .about: "info.circle.fill" }
    }
}

private enum EditorStyle {
    static let background = Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
    static let selectedRow = Color(red: 61 / 255, green: 61 / 255, blue: 61 / 255)
    static let separator = Color.white.opacity(0.13)
}

struct EditorColumns {
    static let navigation: CGFloat = 68
    let sidebar: CGFloat
    let ring: CGFloat
    let editor: CGFloat

    init(width: CGFloat) {
        let shrink = min(1, max(0, (960 - width) / 80))
        sidebar = 200 - 10 * shrink
        editor = width < 960 ? 280 - 20 * shrink : min(420, 280 + (width - 960) / 3)
        ring = max(0, width - Self.navigation - sidebar - editor - 3)
    }
}

// Window-session state only; configuration order remains the source of truth.
struct SnippetEditorSession: Equatable {
    static let pageSize = 8
    var selectedID: UUID?
    var page = 0

    static func pageCount(_ count: Int) -> Int { max(1, (count + pageSize - 1) / pageSize) }

    mutating func select(_ id: UUID?, in ids: [UUID]) {
        selectedID = id
        reconcile(ids)
    }
    mutating func showPage(_ requested: Int, in ids: [UUID]) {
        page = min(max(0, requested), Self.pageCount(ids.count) - 1)
        selectedID = ids.isEmpty ? nil : ids[page * Self.pageSize]
    }
    mutating func reconcile(_ ids: [UUID]) {
        page = min(max(0, page), Self.pageCount(ids.count) - 1)
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            page = index / Self.pageSize
        } else {
            selectedID = ids.isEmpty ? nil : ids[page * Self.pageSize]
        }
    }
    mutating func deleted(at index: Int, remaining ids: [UUID]) {
        select(ids.isEmpty ? nil : ids[min(index, ids.count - 1)], in: ids)
    }
}

// Every deletion entry point requests the same confirmation before changing data.
struct SnippetDeletion {
    private(set) var id: UUID?
    mutating func request(_ id: UUID) { self.id = id }
    mutating func cancel() { id = nil }
    mutating func confirm(_ confirmedID: UUID, profile: inout AppProfile, session: inout SnippetEditorSession) {
        defer { id = nil }
        guard let index = profile.buttons.firstIndex(where: { $0.id == confirmedID }) else { return }
        profile.buttons.remove(at: index)
        session.deleted(at: index, remaining: profile.buttons.map(\.id))
    }
}

struct EditorRingLayout {
    static let buttonSize = CGSize(width: 88, height: 36)
    static let cornerRadius: CGFloat = 12
    let items: [CGRect]

    // Distance between the actual rounded edges, rather than between centers.
    static func edgeGap(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let dx = max(0, abs(first.midX - second.midX) - (first.width - 2 * cornerRadius))
        let dy = max(0, abs(first.midY - second.midY) - (first.height - 2 * cornerRadius))
        return hypot(dx, dy) - 2 * cornerRadius
    }

    init(size: CGSize, count: Int) {
        guard count > 0, count <= SnippetEditorSession.pageSize else { items = []; return }
        let radius = max(0, min(140, (size.width - Self.buttonSize.width - 48) / 2,
                                (size.height - Self.buttonSize.height - 48) / 2))
        func rect(at angle: CGFloat) -> CGRect {
            CGRect(x: size.width / 2 + sin(angle) * radius - Self.buttonSize.width / 2,
                   y: size.height / 2 - cos(angle) * radius - Self.buttonSize.height / 2,
                   width: Self.buttonSize.width, height: Self.buttonSize.height)
        }
        func nextAngle(after angle: CGFloat, gap: CGFloat) -> CGFloat {
            let first = rect(at: angle)
            var low: CGFloat = 0, high = CGFloat.pi
            guard Self.edgeGap(first, rect(at: angle + high)) >= gap else { return .infinity }
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if Self.edgeGap(first, rect(at: angle + middle)) < gap { low = middle }
                else { high = middle }
            }
            return angle + (low + high) / 2
        }
        guard count > 2 else {
            items = (0..<count).map { rect(at: CGFloat($0) * 2 * .pi / CGFloat(count)) }
            return
        }
        // Solve the common clearance that closes one complete circle.
        var low: CGFloat = 0, high = radius * 2
        for _ in 0..<28 {
            let gap = (low + high) / 2
            var angle: CGFloat = 0
            for _ in 0..<count {
                angle = nextAngle(after: angle, gap: gap)
                if !angle.isFinite { break }
            }
            if angle > 2 * .pi { high = gap } else { low = gap }
        }
        let gap = (low + high) / 2
        var angle: CGFloat = 0
        var placed = [rect(at: angle)]
        for _ in 1..<count {
            angle = nextAngle(after: angle, gap: gap)
            placed.append(rect(at: angle))
        }
        items = placed
    }
}

private struct NavigationRail: View {
    @Binding var page: MainPage
    var body: some View {
        VStack(spacing: 12) {
            ForEach(MainPage.allCases, id: \.self) { item in
                Button { page = item } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(page == item ? Color.primary : Color.secondary)
                        .frame(width: 44, height: 44)
                        .background(page == item ? Color.white.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 13))
                        .frame(width: EditorColumns.navigation)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(item.title).accessibilityLabel(item.title)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(width: EditorColumns.navigation)
        .frame(maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var page: MainPage = .home
    @State private var selectedProfile: UUID?
    @State private var sessions: [UUID: SnippetEditorSession] = [:]
    @State private var deleteProfile: UUID?
    @State private var recoveryAlert = false

    init(coordinator: AppCoordinator, initialPage: MainPage = .home) {
        self.coordinator = coordinator
        _page = State(initialValue: initialPage)
        let profiles = coordinator.store.configuration.profiles
        _selectedProfile = State(initialValue: profiles.first?.id)
        _sessions = State(initialValue: Dictionary(uniqueKeysWithValues: profiles.map {
            ($0.id, SnippetEditorSession(selectedID: $0.buttons.first?.id))
        }))
    }

    var body: some View {
        HStack(spacing: 0) {
            NavigationRail(page: $page)
            EditorStyle.separator.frame(width: 1)
            VStack(spacing: 0) {
                if let message = coordinator.store.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                        HStack {
                            Button("恢复最近备份") { recoveryAlert = true }
                            if coordinator.store.isReady {
                                Button("重试保存") { Task { _ = await coordinator.store.flush() } }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.orange.opacity(0.08))
                }
                Group {
                    switch page {
                    case .home:
                        HomePage(coordinator: coordinator, selectedProfile: $selectedProfile,
                                 sessions: $sessions, requestDelete: { deleteProfile = $0 })
                    case .settings: SettingsPage(coordinator: coordinator)
                    case .about: AboutPage()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .background(EditorStyle.background)
        .preferredColorScheme(.dark)
        .disabled(coordinator.isRestarting)
        .onAppear { reconcileProfiles() }
        .onChange(of: coordinator.store.configuration.profiles.map(\.id)) { _, _ in reconcileProfiles() }
        .alert("移除应用及其全部文案？", isPresented: Binding(
            get: { deleteProfile != nil }, set: { if !$0 { deleteProfile = nil } }), presenting: deleteProfile) { id in
                Button("取消", role: .cancel) { deleteProfile = nil }
                Button("移除", role: .destructive) {
                    coordinator.store.configuration.profiles.removeAll { $0.id == id }
                    deleteProfile = nil
                }
            } message: { id in
                Text(coordinator.store.configuration.profiles.first(where: { $0.id == id })?.displayName ?? "")
            }
        .alert("从最近有效备份恢复？", isPresented: $recoveryAlert) {
            Button("取消", role: .cancel) { }
            Button("恢复") { Task { await coordinator.store.restoreBackup() } }
        } message: { Text("当前文件会保留，然后写入备份配置。") }
    }

    private func reconcileProfiles() {
        let ids = coordinator.store.configuration.profiles.map(\.id)
        if selectedProfile == nil || !ids.contains(selectedProfile!) { selectedProfile = ids.first }
        sessions = sessions.filter { ids.contains($0.key) }
        for profile in coordinator.store.configuration.profiles {
            var session = sessions[profile.id] ?? SnippetEditorSession()
            session.reconcile(profile.buttons.map(\.id))
            sessions[profile.id] = session
        }
    }
}

private struct HomePage: View {
    @Bindable var coordinator: AppCoordinator
    @Binding var selectedProfile: UUID?
    @Binding var sessions: [UUID: SnippetEditorSession]
    let requestDelete: (UUID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let columns = EditorColumns(width: geometry.size.width + EditorColumns.navigation + 1)
            HStack(spacing: 0) {
                ApplicationList(coordinator: coordinator, selectedProfile: $selectedProfile,
                                requestDelete: requestDelete)
                    .frame(width: columns.sidebar)
                EditorStyle.separator.frame(width: 1)
                if let profile = coordinator.store.configuration.profiles.first(where: { $0.id == selectedProfile }) {
                    let id = profile.id
                    ProfileEditor(profile: Binding(
                        get: { coordinator.store.configuration.profiles.first(where: { $0.id == id }) ?? profile },
                        set: { updated in
                            if let index = coordinator.store.configuration.profiles.firstIndex(where: { $0.id == id }) {
                                coordinator.store.configuration.profiles[index] = updated
                            }
                        }),
                        session: Binding(get: { sessions[id] ?? SnippetEditorSession() },
                                         set: { sessions[id] = $0 }),
                        editorWidth: columns.editor,
                        saveStatus: coordinator.store.saveStatus)
                        .id(id).disabled(!coordinator.store.isReady)
                } else {
                    EditorEmptyState(title: "添加应用", symbol: "app.badge", action: coordinator.chooseApplications)
                }
            }
        }
    }
}

private struct ApplicationList: View {
    @Bindable var coordinator: AppCoordinator
    @Binding var selectedProfile: UUID?
    let requestDelete: (UUID) -> Void

    var body: some View {
        @Bindable var store = coordinator.store
        VStack(alignment: .leading, spacing: 18) {
            Text("应用列表").font(.system(size: 18, weight: .medium)).padding(.top, 10)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($store.configuration.profiles) { $profile in
                        ZStack(alignment: .trailing) {
                            Button { selectedProfile = profile.id } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: profile.lastKnownBundlePath ?? ""))
                                        .resizable().frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.displayName).font(.system(size: 13)).lineLimit(1)
                                        Text("\(profile.buttons.count) 条文案")
                                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .layoutPriority(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.leading, 10).padding(.trailing, 34)
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选择应用 \(profile.displayName)").help(profile.displayName)
                            Toggle("启用 \(profile.displayName)", isOn: $profile.isEnabled)
                                .toggleStyle(.checkbox).labelsHidden().help("启用或停用此应用")
                                .padding(.trailing, 10)
                        }
                        .background(selectedProfile == profile.id ? EditorStyle.selectedRow : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .contextMenu {
                            Button("移除应用…", role: .destructive) { requestDelete(profile.id) }
                        }
                    }
                }
            }
            .disabled(!coordinator.store.isReady)
            VStack(alignment: .leading, spacing: 16) {
                Menu {
                    Button("选择 .app 文件…", action: coordinator.chooseApplications)
                    Menu("正在运行的应用") {
                        ForEach(NSWorkspace.shared.runningApplications.filter {
                            $0.activationPolicy == .regular && $0.bundleURL != nil
                        }, id: \.processIdentifier) { app in
                            Button(app.localizedName ?? "应用") {
                                if let url = app.bundleURL { coordinator.addApplication(url) }
                            }
                        }
                    }
                } label: { Label("添加应用", systemImage: "plus") }
                    .menuStyle(.borderlessButton).disabled(!coordinator.store.isReady)

            }
            .padding(.bottom, 8)
        }
        .padding(16)
    }
}

private struct EditorEmptyState: View {
    let title: String
    let symbol: String
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            if let action { Button(title, action: action).buttonStyle(.borderless) }
            else { Text(title).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProfileEditor: View {
    @Binding var profile: AppProfile
    @Binding var session: SnippetEditorSession
    let editorWidth: CGFloat
    var saveStatus = "已保存"
    @State private var deletion = SnippetDeletion()

    private var ids: [UUID] { profile.buttons.map(\.id) }
    private var pages: Int { SnippetEditorSession.pageCount(profile.buttons.count) }
    private var visibleSnippets: [Snippet] {
        Array(profile.buttons.dropFirst(session.page * SnippetEditorSession.pageSize).prefix(SnippetEditorSession.pageSize))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Picker("触发方式", selection: $profile.displayMode) {
                        Text("修饰键").tag(DisplayMode.modifierClick)
                        Text("快捷键").tag(DisplayMode.shortcutOnly)
                    }
                    .pickerStyle(.menu).labelsHidden().frame(width: 100)
                    .help("\(profile.displayName) 的触发方式")
                    .accessibilityLabel("\(profile.displayName) 的触发方式")
                    Spacer()
                    Button(action: addSnippet) { Label("添加文案", systemImage: "plus") }
                        .buttonStyle(.plain).font(.system(size: 12))
                }
                .foregroundStyle(.secondary).padding(.horizontal, 22).frame(height: 56)
                GeometryReader { geometry in
                    let snippets = visibleSnippets
                    let layout = EditorRingLayout(size: geometry.size, count: snippets.count)
                    if snippets.isEmpty {
                        EditorEmptyState(title: "添加文案", symbol: "text.badge.plus", action: addSnippet)
                    } else {
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(.secondary)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                            let rect = layout.items[index]
                            EditorSnippetButton(snippet: snippet, selected: session.selectedID == snippet.id, size: rect.size) {
                                session.select(snippet.id, in: ids)
                            }
                            .contextMenu { snippetActions(snippet.id) }
                            .position(x: rect.midX, y: rect.midY)
                            if session.selectedID == snippet.id {
                                Button(role: .destructive) { deletion.request(snippet.id) } label: {
                                    Label("删除", systemImage: "trash")
                                        .font(.system(size: 11)).frame(width: 60, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).foregroundStyle(.red)
                                .help("删除文案 \(snippet.title)")
                                .accessibilityLabel("删除选中的环形文案")
                                .position(x: rect.midX, y: rect.maxY + 14)
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    if pages > 1 {
                        Button { session.showPage(session.page - 1, in: ids) } label: { Image(systemName: "chevron.left") }
                            .disabled(session.page == 0).help("上一页").accessibilityLabel("上一页")
                        Text("\(session.page + 1) / \(pages)").monospacedDigit()
                        Button { session.showPage(session.page + 1, in: ids) } label: { Image(systemName: "chevron.right") }
                            .disabled(session.page == pages - 1).help("下一页").accessibilityLabel("下一页")
                    }
                }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(height: 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            EditorStyle.separator.frame(width: 1)
            Group {
                if let snippet = profile.buttons.first(where: { $0.id == session.selectedID }) {
                    let binding = Binding(get: { profile.buttons.first(where: { $0.id == snippet.id }) ?? snippet },
                                          set: { updated in
                                              if let index = profile.buttons.firstIndex(where: { $0.id == snippet.id }) {
                                                  profile.buttons[index] = updated
                                              }
                                          })
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("标题").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("输入文案标题", text: binding.title, axis: .vertical)
                                .textFieldStyle(.plain).font(.system(size: 18, weight: .medium))
                                .lineLimit(1...3)
                                .accessibilityLabel("文案标题")
                        }
                        Color.white.opacity(0.08).frame(height: 1)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("正文").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextEditor(text: binding.text)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .lineSpacing(4).scrollContentBackground(.hidden)
                                // NSTextView adds 5 pt of line-fragment padding on each side.
                                .padding(.horizontal, -5)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilityLabel("文案正文")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        HStack(alignment: .firstTextBaseline) {
                            Text(saveStatus)
                            Spacer(minLength: 4)
                            Text("\(snippet.text.utf8.count) B / 64 KiB").monospacedDigit()
                            Button(role: .destructive) { deletion.request(snippet.id) } label: {
                                Image(systemName: "trash").frame(width: 24, height: 24).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(.red)
                            .help("删除文案 \(snippet.title)")
                            .accessibilityLabel("删除当前编辑文案")
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(22)
                } else {
                    EditorEmptyState(title: "选择文案开始编辑", symbol: "text.alignleft")
                }
            }
            .frame(width: editorWidth)
            .frame(maxHeight: .infinity)
        }
        .onAppear { session.reconcile(ids) }
        .onChange(of: ids) { _, updated in session.reconcile(updated) }
        .alert("删除这条文案？", isPresented: Binding(get: { deletion.id != nil },
            set: { if !$0 { deletion.cancel() } }), presenting: deletion.id) { id in
                Button("取消", role: .cancel) { deletion.cancel() }
                Button("删除", role: .destructive) {
                    deletion.confirm(id, profile: &profile, session: &session)
                }
            } message: { id in
                Text(profile.buttons.first(where: { $0.id == id })?.title ?? "")
            }

    }

    @ViewBuilder private func snippetActions(_ id: UUID) -> some View {
        Button("复制文案") { duplicate(id) }
        Button("上移") { move(id, by: -1) }.disabled(ids.first == id)
        Button("下移") { move(id, by: 1) }.disabled(ids.last == id)
        Divider()
        Button("删除文案…", role: .destructive) { deletion.request(id) }
    }
    private func addSnippet() {
        let snippet = Snippet(title: "新文案", text: "在这里填写要插入的内容。")
        profile.buttons.append(snippet)
        session.select(snippet.id, in: ids)
    }
    private func duplicate(_ id: UUID) {
        guard var snippet = profile.buttons.first(where: { $0.id == id }) else { return }
        snippet.id = UUID(); snippet.title += " 副本"
        profile.buttons.append(snippet)
        session.select(snippet.id, in: ids)
    }
    private func move(_ id: UUID, by distance: Int) {
        guard let index = ids.firstIndex(of: id), profile.buttons.indices.contains(index + distance) else { return }
        profile.buttons.swapAt(index, index + distance)
        session.select(id, in: ids)
    }
}

private struct EditorSnippetButton: View {
    let snippet: Snippet
    let selected: Bool
    let size: CGSize
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(floatingButtonTitle(snippet.title)).font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.black.opacity(0.9) : Color.white.opacity(0.8)).lineLimit(1)
                .frame(width: size.width, height: size.height)
                .background(Color(white: selected ? (hovering ? 0.98 : 0.92) : (hovering ? 0.42 : 0.32)),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                    selected ? Color.white : Color.clear, lineWidth: 2))
                .opacity(snippet.isEnabled ? 1 : (selected ? 0.7 : 0.45))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help(snippet.title).accessibilityLabel(snippet.title)
        .accessibilityValue(snippet.isEnabled ? "已启用" : "已停用")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct SettingsPage: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader("设置", subtitle: "管理快捷栏、系统权限和启动方式")

                SurfaceCard(title: "触发条件", symbol: "cursorarrow.click") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("启用快捷栏", isOn: Binding(
                            get: { coordinator.store.configuration.preferences.isEnabled },
                            set: { coordinator.store.configuration.preferences.isEnabled = $0 }))
                            .disabled(!coordinator.store.isReady)
                        Divider()
                        Picker("按住展开的触发键", selection: Binding(
                            get: { coordinator.store.configuration.preferences.clickModifier },
                            set: { coordinator.store.configuration.preferences.clickModifier = $0 })) {
                            Text("Option ⌥").tag(ClickModifier.option)
                            Text("Command ⌘").tag(ClickModifier.command)
                            Text("Shift ⇧").tag(ClickModifier.shift)
                        }
                        .disabled(!coordinator.store.isReady)
                        Picker("展开位置", selection: Binding(
                            get: { coordinator.store.configuration.preferences.menuAnchorMode },
                            set: { coordinator.store.configuration.preferences.menuAnchorMode = $0 })) {
                            ForEach(MenuAnchorMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .disabled(!coordinator.store.isReady)
                        Text(coordinator.store.configuration.preferences.menuAnchorMode == .mouse
                             ? "先点入输入框，将鼠标放在其中。按住触发键展开，移到文案按钮，松开后粘贴；未选中则取消。"
                             : "先点入输入框。按住触发键从输入光标处展开，再移动鼠标选择文案，松开后粘贴。无法定位光标时改用鼠标位置。")
                            .font(.caption).foregroundStyle(.secondary)
                        KeyboardShortcuts.Recorder("按住展开的快捷键", name: .toggleFloatingInputBar)
                    }
                }

                SurfaceCard(title: "系统权限", symbol: "hand.raised") {
                    VStack(alignment: .leading, spacing: 13) {
                        PermissionRow(step: coordinator.authorizationStep,
                                      detail: coordinator.authorizationDetail,
                                      isRestarting: coordinator.isRestarting,
                                      action: coordinator.performAuthorizationAction)
                        if !coordinator.mouseMonitorAvailable {
                            Text("鼠标触发暂不可用，仍可使用上方录制的快捷键。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                SurfaceCard(title: "启动与显示", symbol: "rectangle.on.rectangle") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("登录时启动", isOn: Binding(
                            get: { coordinator.loginEnabled },
                            set: { coordinator.setLoginEnabled($0) }))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                        Toggle("在 Dock 中显示图标", isOn: Binding(
                            get: { coordinator.dockIconVisible },
                            set: { coordinator.setDockIconVisible($0) }))
                            .disabled(!coordinator.menuBarIconVisible)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("在菜单栏显示图标", isOn: Binding(
                            get: { coordinator.menuBarIconVisible },
                            set: { coordinator.setMenuBarIconVisible($0) }))
                            .disabled(!coordinator.dockIconVisible)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("请至少保留 Dock 或菜单栏中的一个入口。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                SurfaceCard(title: "配置", symbol: "externaldrive") {
                    HStack(spacing: 10) {
                        Button("导入配置…", action: coordinator.importConfiguration)
                        Button("导出配置…", action: coordinator.exportConfiguration)
                        Spacer()
                        Text("配置保存在本机")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PermissionRow: View {
    var step: AuthorizationFlow.Step
    var detail: String
    var isRestarting = false
    var action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(step == .ready ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("辅助功能").fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            if step == .ready {
                Text(step.title).foregroundStyle(.green)
            } else {
                Button(isRestarting ? "正在重启…" : step.title, action: action).disabled(isRestarting)
            }
        }
    }
}

private struct AboutPage: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().interpolation(.high).frame(width: 112, height: 112)
            Text("PhrasePerch").font(.largeTitle.weight(.semibold))
            Text("按应用管理快捷文案").font(.callout).foregroundStyle(.secondary)
            Text("v\(version)").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SurfaceCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.055), lineWidth: 1))
    }
}

private func pageHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.largeTitle.weight(.semibold))
        Text(subtitle).font(.callout).foregroundStyle(.secondary)
    }
}
