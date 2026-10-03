import Darwin
import Foundation
import Observation

@MainActor @Observable
final class AuthorizationService {
    let store: ConfigurationRepository
    private(set) var accessibilityGranted = false
    private(set) var postEventsGranted = false
    private(set) var permissionFeedback = ""
    private(set) var isRestarting = false
    private(set) var restartExitReady = false
    private(set) var authorizationFlow: AuthorizationFlow
    var authorizationStep: AuthorizationFlow.Step { authorizationFlow.step }
    var authorizationDetail: String {
        switch authorizationStep {
        case .authorize: "允许读取输入位置并粘贴文案；请在系统设置中添加当前 PhrasePerch 并开启。"
        case .restart: "系统授权已开启，请重启 PhrasePerch 使权限生效。"
        case .ready: "读取输入位置与粘贴文案均已就绪。"
        case .reauthorize: "重启后粘贴仍未就绪；请在系统设置中重新添加当前 PhrasePerch。"
        }
    }
    var authorizationStatus: InputAuthorizationStatus {
        InputAuthorizationStatus(accessibility: accessibilityGranted, paste: postEventsGranted)
    }
    var notice = ""
    var onInvalidate: (() -> Void)?
    private let authorizationGuide: any AuthorizationGuidePresenting
    private var authorizationTask: Task<Void, Never>?
    private var authorizationPending = false
    private var permissionTimer: Timer?
    private var permissionDeadline = Date.distantPast
    private let authorizationEnvironment: AuthorizationEnvironment
    private let authorizationDefaults: UserDefaults
    static let restartPendingKey = "PhrasePerch.authorizationRestartPending"
    var isPending: Bool { authorizationPending }
    var guideVisible: Bool { authorizationGuide.isVisible }

    init(
        store: ConfigurationRepository, guide: any AuthorizationGuidePresenting,
        environment: AuthorizationEnvironment = AuthorizationEnvironment(), defaults: UserDefaults = .standard
    ) {
        self.store = store
        authorizationGuide = guide
        authorizationEnvironment = environment
        authorizationDefaults = defaults
        authorizationFlow = AuthorizationFlow(
            afterRestart: defaults.string(forKey: Self.restartPendingKey) == Bundle.main.bundlePath)
        defaults.removeObject(forKey: Self.restartPendingKey)
        authorizationGuide.onDragEnded = { [weak self] accepted in
            guard let self else { return }
            notice = accepted ? "应用已拖入，请在系统列表中开启开关，再返回重启。" : "尚未添加，请重新拖入应用。"
            refreshPermissions()
            watchAuthorization()
        }
    }
    func cancelGuidance() {
        stopAuthorizationWatch()
        authorizationGuide.hide()
    }

    func refreshPermissions() {
        let previous = authorizationStatus
        let wasTrusted = accessibilityGranted
        let snapshot = authorizationEnvironment.snapshot()
        let trusted = snapshot.accessibility
        let events = snapshot.paste
        if accessibilityGranted && !trusted || postEventsGranted && !events { onInvalidate?() }
        accessibilityGranted = trusted
        postEventsGranted = events
        if authorizationStatus == .ready { stopAuthorizationWatch() }
        if authorizationStatus != previous {
            permissionFeedback = authorizationStatus == .ready ? "权限已就绪，可以使用快捷栏。" : "权限状态已更新。"
        }
        authorizationFlow.refresh(accessibility: trusted, paste: events)
        if (trusted && !wasTrusted) || authorizationStatus == .ready { authorizationGuide.hide() }

    }

    func stopAuthorizationWatch() {
        authorizationTask?.cancel()
        authorizationTask = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        authorizationPending = false
    }

    func watchAuthorization() {
        guard authorizationStatus != .ready else { return }
        authorizationPending = true
        permissionDeadline = Date().addingTimeInterval(20)
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard Date() < self.permissionDeadline else {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    return
                }
                self.refreshPermissions()
            }
        }
    }

    func performAuthorizationAction() {
        refreshPermissions()
        switch authorizationStep {
        case .authorize, .reauthorize: openAuthorizationSettings()
        case .restart: restartForAuthorization()
        case .ready: break
        }
    }

    func openAuthorizationSettings() {
        onInvalidate?()
        refreshPermissions()
        let opened = authorizationEnvironment.openSettings()
        permissionFeedback =
            opened
            ? "请在系统设置中添加并开启当前 PhrasePerch，然后返回应用重启。"
            : "无法打开授权页面。请手动打开系统设置的权限列表，添加并开启当前 PhrasePerch。"
        notice = permissionFeedback
        if opened {
            watchAuthorization()
            authorizationTask = Task { [weak self] in
                for _ in 0..<20 {
                    guard !Task.isCancelled else { return }
                    if self?.authorizationEnvironment.systemSettingsIsFrontmost() == true { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard let self, !Task.isCancelled,
                    authorizationEnvironment.systemSettingsIsFrontmost(),
                    authorizationStep == .authorize || authorizationStep == .reauthorize
                else { return }
                authorizationGuide.show(applicationURL: Bundle.main.bundleURL)
            }
        }
    }

    func restartForAuthorization() {
        guard !isRestarting else { return }
        guard store.isReady else {
            notice = "配置尚未正常加载，已取消重启。请先处理配置读取错误。"
            return
        }
        onInvalidate?()
        isRestarting = true
        permissionFeedback = "正在保存配置并重新启动…"
        Task {
            guard await authorizationEnvironment.save(store) else {
                isRestarting = false
                notice = "配置未保存，已取消重启。请先处理保存错误。"
                return
            }
            do {
                authorizationDefaults.set(Bundle.main.bundlePath, forKey: Self.restartPendingKey)
                try authorizationEnvironment.relaunch(Bundle.main.bundleURL, getpid())
                // Already saved: don't repeat an async save inside AppKit's nested termination loop.
                restartExitReady = true
                authorizationEnvironment.terminate()
            } catch {
                authorizationDefaults.removeObject(forKey: Self.restartPendingKey)
                isRestarting = false
                notice = "重启失败：\(error.localizedDescription)。当前应用仍在运行。"
            }
        }
    }
}
