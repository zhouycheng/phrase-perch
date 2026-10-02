import SwiftUI
import AppKit
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var selectedProfile: UUID?
    @State private var deleteProfile: UUID?
    @State private var recoveryAlert = false

    var body: some View {
        VStack(spacing: 0) {
            if let message = coordinator.store.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("恢复最近备份") { recoveryAlert = true }
                    if coordinator.store.isReady { Button("重试保存") { Task { _ = await coordinator.store.flush() } } }
                }.padding(10).background(Color.orange.opacity(0.12))
            }
            HSplitView {
                VStack(alignment: .leading) {
                    Text("应用规则").font(.headline).padding(.horizontal)
                    List(selection: $selectedProfile) {
                        ForEach(coordinator.store.configuration.profiles) { profile in
                            HStack {
                                if let path = profile.lastKnownBundlePath {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 24, height: 24)
                                }
                                VStack(alignment: .leading) {
                                    Text(profile.displayName)
                                    Text(profile.isEnabled ? "\(profile.buttons.filter(\.isEnabled).count) 个按钮" : "已停用")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.tag(profile.id)
                        }
                    }
                    Menu("添加应用") {
                        Button("选择 .app 文件…", action: coordinator.chooseApplications)
                        Menu("运行中的应用") {
                            ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleURL != nil }, id: \.processIdentifier) { app in
                                Button(app.localizedName ?? "应用") { if let url = app.bundleURL { coordinator.addApplication(url) } }
                            }
                        }
                    }.padding(.horizontal)
                    Button("移除所选应用…") { deleteProfile = selectedProfile }.disabled(selectedProfile == nil)
                        .padding(.horizontal).padding(.bottom)
                }.frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
                    .disabled(!coordinator.store.isReady)
                if let profile = coordinator.store.configuration.profiles.first(where: { $0.id == selectedProfile }) {
                    ProfileEditor(profile: Binding(
                        get: { coordinator.store.configuration.profiles.first(where: { $0.id == profile.id }) ?? profile },
                        set: { updated in
                            if let index = coordinator.store.configuration.profiles.firstIndex(where: { $0.id == profile.id }) {
                                coordinator.store.configuration.profiles[index] = updated
                            }
                        }))
                        .id(selectedProfile)
                        .frame(minWidth: 370, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.badge.plus").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("为应用添加常用文案").font(.title3)
                        Text("从左侧添加应用，然后配置文本按钮。\n按住触发键点击输入框，松开后选择快捷栏文案。")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Text("浏览器规则覆盖整个浏览器；同 Bundle Identifier 的副本共享规则。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding().frame(minWidth: 370, maxWidth: .infinity, maxHeight: .infinity)
                }
                GeneralSettings(coordinator: coordinator).frame(minWidth: 230, idealWidth: 260, maxWidth: 300)
            }
            if !coordinator.notice.isEmpty {
                Text(coordinator.notice).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.quaternary)
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .disabled(coordinator.isRestarting)
        .alert("移除应用及其全部按钮？", isPresented: Binding(get: { deleteProfile != nil }, set: { if !$0 { deleteProfile = nil } })) {
            Button("取消", role: .cancel) { deleteProfile = nil }
            Button("移除", role: .destructive) {
                coordinator.store.configuration.profiles.removeAll { $0.id == deleteProfile }
                selectedProfile = nil; deleteProfile = nil
            }
        } message: {
            Text(coordinator.store.configuration.profiles.first(where: { $0.id == deleteProfile })?.displayName ?? "")
        }
        .alert("从最近有效备份恢复？", isPresented: $recoveryAlert) {
            Button("取消", role: .cancel) { }
            Button("恢复") { Task { await coordinator.store.restoreBackup() } }
        } message: { Text("当前文件会保留，然后写入备份配置。") }

    }
}

struct ProfileEditor: View {
    @Binding var profile: AppProfile
    @State private var selectedSnippet: UUID?
    @State private var deletingSnippet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(profile.displayName).font(.title2); Spacer(); Toggle("启用", isOn: $profile.isEnabled).toggleStyle(.switch) }
            Text(profile.application.bundleIdentifier ?? profile.application.fallbackBundlePath ?? "")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Picker("显示", selection: $profile.displayMode) {
                    Text("修饰键点击＋快捷键").tag(DisplayMode.modifierClick); Text("仅快捷键").tag(DisplayMode.shortcutOnly)
                }
            }
            Text("点击按钮会覆盖系统剪贴板并尝试 ⌘V。文案留在剪贴板；未自动粘贴时可手动 ⌘V，不会自动发送。")
                .font(.caption).foregroundStyle(.secondary)
            List(selection: $selectedSnippet) {
                ForEach(profile.buttons) { button in
                    HStack {
                        Image(systemName: button.isEnabled ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
                        Text(button.title); Spacer(); Text("\(button.text.utf8.count) B").foregroundStyle(.secondary).font(.caption)
                    }.tag(button.id)
                }.onMove { profile.buttons.move(fromOffsets: $0, toOffset: $1) }
            }.frame(minHeight: 100, idealHeight: 160, maxHeight: 200)
            HStack {
                Button("新增") {
                    let button = Snippet(title: "新按钮", text: "请在这里填写正文。")
                    profile.buttons.append(button); selectedSnippet = button.id
                }
                Button("复制") {
                    guard let button = profile.buttons.first(where: { $0.id == selectedSnippet }) else { return }
                    var copy = button; copy.id = UUID(); copy.title += " 副本"
                    profile.buttons.append(copy); selectedSnippet = copy.id
                }.disabled(selectedSnippet == nil)
                Button("删除…") { deletingSnippet = true }.disabled(selectedSnippet == nil)
                Spacer()
                Button("↑") { move(-1) }.disabled(selectedSnippet == nil)
                Button("↓") { move(1) }.disabled(selectedSnippet == nil)
            }
            if let index = profile.buttons.firstIndex(where: { $0.id == selectedSnippet }) {
                TextField("按钮名称", text: $profile.buttons[index].title)
                Toggle("按钮启用", isOn: $profile.buttons[index].isEnabled)
                TextEditor(text: $profile.buttons[index].text).font(.body)
                    .frame(minHeight: 100).border(.quaternary)
                Text("纯文本，最多 64 KiB；自动保存。不会自动发送。")
                    .font(.caption).foregroundStyle(.secondary)
            } else { Text("选择按钮编辑正文").foregroundStyle(.secondary); Spacer() }
        }.padding()
        .alert("删除所选按钮？", isPresented: $deletingSnippet) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) { profile.buttons.removeAll { $0.id == selectedSnippet }; selectedSnippet = nil }
        } message: { Text(profile.buttons.first(where: { $0.id == selectedSnippet })?.title ?? "") }
    }
    private func move(_ distance: Int) {
        guard let index = profile.buttons.firstIndex(where: { $0.id == selectedSnippet }),
              profile.buttons.indices.contains(index + distance) else { return }
        profile.buttons.swapAt(index, index + distance)
    }
}

struct GeneralSettings: View {
    @Bindable var coordinator: AppCoordinator
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("PhrasePerch").font(.headline)
                    Spacer()
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("启用PhrasePerch", isOn: Binding(get: { coordinator.store.configuration.preferences.isEnabled },
                                                      set: { coordinator.store.configuration.preferences.isEnabled = $0 }))
                    .disabled(!coordinator.store.isReady)
                KeyboardShortcuts.Recorder("显示／收起快捷栏", name: .toggleFloatingInputBar)
                Picker("点击输入框的触发键", selection: Binding(
                    get: { coordinator.store.configuration.preferences.clickModifier },
                    set: { coordinator.store.configuration.preferences.clickModifier = $0 })) {
                    Text("Option ⌥").tag(ClickModifier.option)
                    Text("Command ⌘").tag(ClickModifier.command)
                    Text("Shift ⇧").tag(ClickModifier.shift)
                }.disabled(!coordinator.store.isReady)
                Text("按住触发键点击输入框或拖动选择文字，松开后选择文案；粘贴指令发出后自动收起。普通点击不显示。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("登录时启动", isOn: Binding(get: { coordinator.loginEnabled }, set: coordinator.setLoginEnabled))
                Divider()
                AuthorizationCard(status: coordinator.authorizationStatus,
                    restarting: coordinator.isRestarting) { action in
                        switch action {
                        case .settings: coordinator.openAuthorizationSettings()
                        case .restart: coordinator.restartForAuthorization()
                        }
                    }
                if !coordinator.mouseMonitorAvailable {
                    Text("鼠标观察不可用，使用快捷键显示。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Button("导入配置…", action: coordinator.importConfiguration)
                Button("导出配置…", action: coordinator.exportConfiguration)
                Text("所有文案通过剪贴板粘贴，单条最多 64 KiB；中文组词候选状态请先手动提交。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
    }
}

enum AuthorizationAction { case settings, restart }

struct AuthorizationCard: View {
    let status: InputAuthorizationStatus
    let restarting: Bool
    let action: (AuthorizationAction) -> Void

    var body: some View {
        HStack {
            Label(status.title, systemImage: status == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status == .ready ? Color.green : Color.orange)
            Spacer()
            if status == .needsAccessibility {
                Button("授权") { action(.settings) }.buttonStyle(.borderedProminent)
            } else if status == .needsPasteAccess {
                Button(restarting ? "正在重启…" : "重启生效") { action(.restart) }
            }
        }.disabled(restarting)
    }
}
