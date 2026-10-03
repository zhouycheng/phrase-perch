import SwiftUI
import AppKit
import KeyboardShortcuts

private enum MainPage: String, CaseIterable, Hashable {
    case home, settings, about

    var title: String {
        switch self {
        case .home: "首页"
        case .settings: "设置"
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .settings: "gearshape.fill"
        case .about: "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var page: MainPage = .home
    @State private var selectedProfile: UUID?
    @State private var deleteProfile: UUID?
    @State private var recoveryAlert = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                ForEach(MainPage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(page == item ? Color.primary : Color.secondary)
                            .frame(width: 44, height: 44)
                            .background(page == item ? Color.white.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .help(item.title)
                    .accessibilityLabel(item.title)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .frame(width: 68)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))

            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)

            VStack(spacing: 0) {
                if let message = coordinator.store.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button("恢复最近备份") { recoveryAlert = true }
                        if coordinator.store.isReady {
                            Button("重试保存") { Task { _ = await coordinator.store.flush() } }
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                }

                Group {
                    switch page {
                    case .home:
                        HomePage(coordinator: coordinator, selectedProfile: $selectedProfile) {
                            deleteProfile = $0
                        }
                    case .settings:
                        SettingsPage(coordinator: coordinator)
                    case .about:
                        AboutPage()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !coordinator.notice.isEmpty {
                    Text(coordinator.notice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: .controlBackgroundColor))
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .disabled(coordinator.isRestarting)
        .onAppear { selectFirstProfileIfNeeded() }
        .onChange(of: coordinator.store.configuration.profiles.map(\.id)) { _, ids in
            if let selectedProfile, !ids.contains(selectedProfile) {
                self.selectedProfile = ids.first
            } else {
                selectFirstProfileIfNeeded()
            }
        }
        .alert("移除应用及其全部按钮？", isPresented: Binding(
            get: { deleteProfile != nil }, set: { if !$0 { deleteProfile = nil } })) {
                Button("取消", role: .cancel) { deleteProfile = nil }
                Button("移除", role: .destructive) {
                    coordinator.store.configuration.profiles.removeAll { $0.id == deleteProfile }
                    selectedProfile = coordinator.store.configuration.profiles.first?.id
                    deleteProfile = nil
                }
            } message: {
                Text(coordinator.store.configuration.profiles.first(where: { $0.id == deleteProfile })?.displayName ?? "")
            }
        .alert("从最近有效备份恢复？", isPresented: $recoveryAlert) {
            Button("取消", role: .cancel) { }
            Button("恢复") { Task { await coordinator.store.restoreBackup() } }
        } message: { Text("当前文件会保留，然后写入备份配置。") }
    }

    private func selectFirstProfileIfNeeded() {
        if selectedProfile == nil { selectedProfile = coordinator.store.configuration.profiles.first?.id }
    }
}

private struct HomePage: View {
    @Bindable var coordinator: AppCoordinator
    @Binding var selectedProfile: UUID?
    let requestDelete: (UUID) -> Void

    private var selectedApp: AppProfile? {
        coordinator.store.configuration.profiles.first { $0.id == selectedProfile }
            ?? coordinator.store.configuration.profiles.first
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 16) {
                MenuBarPreview(profile: selectedApp)

                HSplitView {
                    ApplicationList(coordinator: coordinator, selectedProfile: $selectedProfile,
                                    requestDelete: requestDelete)
                        .frame(minWidth: 165, idealWidth: 185, maxWidth: 205)

                    if let profile = selectedApp {
                        ProfileEditor(profile: Binding(
                            get: { coordinator.store.configuration.profiles.first(where: { $0.id == profile.id }) ?? profile },
                            set: { updated in
                                if let index = coordinator.store.configuration.profiles.firstIndex(where: { $0.id == profile.id }) {
                                    coordinator.store.configuration.profiles[index] = updated
                                }
                            }))
                            .id(profile.id)
                            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "text.badge.plus").font(.system(size: 34)).foregroundStyle(.secondary)
                            Text("添加应用以设置快捷文案").font(.title3.weight(.medium))
                            Text("为不同应用配置各自的文案和触发方式。")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .frame(minHeight: 390, maxHeight: .infinity)
            }
            .padding(26)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}

private struct MenuBarPreview: View {
    let profile: AppProfile?
    private var snippets: [Snippet] { Array((profile?.buttons.filter(\.isEnabled) ?? []).prefix(5)) }
    private var hasMore: Bool { (profile?.buttons.filter(\.isEnabled).count ?? 0) > 5 }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if snippets.isEmpty {
                    Text("启用的文案会显示在这里")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                } else {
                    ForEach(snippets.indices, id: \.self) { index in
                        if index > 0 { previewSeparator }
                        Text(floatingButtonTitle(snippets[index].title))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 17)
                    }
                }
                if hasMore {
                    previewSeparator
                    Text("•••").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14)
                }
                previewSeparator
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 42)
            }
            .frame(height: 44)
            .background(Color.black.opacity(0.24), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.11), lineWidth: 1))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var previewSeparator: some View {
        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 18)
    }
}

private struct ApplicationList: View {
    @Bindable var coordinator: AppCoordinator
    @Binding var selectedProfile: UUID?
    let requestDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("应用").font(.subheadline.weight(.medium))
                Spacer()
                Text("\(coordinator.store.configuration.profiles.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            List(selection: $selectedProfile) {
                ForEach(coordinator.store.configuration.profiles) { profile in
                    HStack(spacing: 10) {
                        if let path = profile.lastKnownBundlePath {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable().frame(width: 30, height: 30)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.displayName).lineLimit(1)
                            Text(profile.isEnabled ? "\(profile.buttons.filter(\.isEnabled).count) 条文案" : "已停用")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .tag(profile.id)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120, maxHeight: .infinity)

            HStack(spacing: 8) {
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
                } label: {
                    Label("添加应用", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .disabled(!coordinator.store.isReady)

                Spacer(minLength: 0)
                Button {
                    if let selectedProfile { requestDelete(selectedProfile) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("移除所选应用")
                .disabled(selectedProfile == nil || !coordinator.store.isReady)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(!coordinator.store.isReady)
    }
}

private struct ProfileEditor: View {
    @Binding var profile: AppProfile
    @State private var selectedSnippet: UUID?
    @State private var deletingSnippet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let path = profile.lastKnownBundlePath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable().frame(width: 30, height: 30)
                }
                Text(profile.displayName).font(.headline)
                Spacer()
                Toggle("启用应用", isOn: $profile.isEnabled).labelsHidden()
                    .help("启用此应用的快捷栏")
            }

            Picker("触发方式", selection: $profile.displayMode) {
                Text("按住修饰键或快捷键").tag(DisplayMode.modifierClick)
                Text("仅按住快捷键").tag(DisplayMode.shortcutOnly)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380, alignment: .leading)

            Divider()
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("快捷文案").font(.headline)
                        Spacer()
                        Text("\(profile.buttons.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }

                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(profile.buttons) { button in
                                snippetRow(button)
                            }
                        }
                        .padding(5)
                    }
                    .frame(minHeight: 120, maxHeight: .infinity)
                    .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

                    HStack(spacing: 8) {
                        Button {
                            let button = Snippet(title: "新文案", text: "在这里填写要插入的内容。")
                            profile.buttons.append(button)
                            selectedSnippet = button.id
                        } label: {
                            Label("添加文案", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            guard let button = profile.buttons.first(where: { $0.id == selectedSnippet }) else { return }
                            var copy = button
                            copy.id = UUID(); copy.title += " 副本"
                            profile.buttons.append(copy); selectedSnippet = copy.id
                        } label: { Image(systemName: "plus.square.on.square") }
                            .buttonStyle(.bordered).controlSize(.small)
                            .help("复制所选文案条目").accessibilityLabel("复制所选文案条目")
                            .disabled(selectedSnippet == nil)
                        Button(role: .destructive) { deletingSnippet = true } label: { Image(systemName: "trash") }
                            .buttonStyle(.bordered).controlSize(.small)
                            .help("删除文案").disabled(selectedSnippet == nil)
                        Spacer(minLength: 0)
                        Button { move(-1) } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(.borderless).help("上移").disabled(selectedSnippet == nil)
                        Button { move(1) } label: { Image(systemName: "arrow.down") }
                            .buttonStyle(.borderless).help("下移").disabled(selectedSnippet == nil)
                    }
                }
                .frame(width: 220)

                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)

                if let index = profile.buttons.firstIndex(where: { $0.id == selectedSnippet }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            TextField("快捷栏标题", text: $profile.buttons[index].title)
                                .font(.title3.weight(.semibold))
                            Toggle("在快捷栏显示", isOn: $profile.buttons[index].isEnabled)
                                .fixedSize()
                        }
                        Text("插入内容").font(.headline)
                        TextEditor(text: $profile.buttons[index].text)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 160, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                        HStack {
                            Text("纯文本 · 最多 64 KiB · 自动保存")
                            Spacer()
                            Text("\(profile.buttons[index].text.utf8.count) B")
                                .monospacedDigit()
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "text.alignleft").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("添加一条快捷文案开始编辑")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { selectFirstSnippetIfNeeded() }
        .onChange(of: profile.buttons.map(\.id)) { _, ids in
            if let selectedSnippet, !ids.contains(selectedSnippet) { self.selectedSnippet = ids.first }
            else { selectFirstSnippetIfNeeded() }
        }
        .alert("删除所选文案？", isPresented: $deletingSnippet) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                profile.buttons.removeAll { $0.id == selectedSnippet }
                selectedSnippet = profile.buttons.first?.id
            }
        } message: {
            Text(profile.buttons.first(where: { $0.id == selectedSnippet })?.title ?? "")
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        let selected = selectedSnippet == snippet.id
        return Button { selectedSnippet = snippet.id } label: {
            HStack(spacing: 8) {
                Image(systemName: snippet.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(snippet.isEnabled ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.title).lineLimit(1)
                    Text("\(snippet.text.utf8.count) B").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? Color.white.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityLabel(snippet.title)
    }

    private func selectFirstSnippetIfNeeded() {
        if selectedSnippet == nil { selectedSnippet = profile.buttons.first?.id }
    }

    private func move(_ distance: Int) {
        guard let index = profile.buttons.firstIndex(where: { $0.id == selectedSnippet }),
              profile.buttons.indices.contains(index + distance) else { return }
        profile.buttons.swapAt(index, index + distance)
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
