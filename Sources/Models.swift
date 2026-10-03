import Foundation
import CoreGraphics

enum DisplayMode: String, Codable, CaseIterable, Sendable { case modifierClick, shortcutOnly }

enum InputAuthorizationStatus: Equatable {
    case needsAccessibility, needsPasteAccess, ready
    init(accessibility: Bool, paste: Bool) {
        self = !accessibility ? .needsAccessibility : (!paste ? .needsPasteAccess : .ready)
    }
    var title: String {
        switch self {
        case .needsAccessibility: "未授权"
        case .needsPasteAccess: "授权待生效"
        case .ready: "已授权"
        }
    }
}

enum ClickModifier: String, Codable, CaseIterable, Sendable {
    case option, command, shift
    var mask: UInt {
        switch self {
        case .option: UInt(CGEventFlags.maskAlternate.rawValue)
        case .command: UInt(CGEventFlags.maskCommand.rawValue)
        case .shift: UInt(CGEventFlags.maskShift.rawValue)
        }
    }
}

// One token follows a hold from the AX check through the eventual paste. Late
// callbacks and duplicate releases cannot advance a different hold.
struct HoldMenuSession {
    static let modifierReleaseTimeout: Duration = .milliseconds(500)
    enum Trigger: Equatable { case modifier, shortcut }
    enum Phase: Equatable { case idle, checking, choosing, waitingForModifiers, inserting }
    private(set) var id: UUID?
    private(set) var trigger: Trigger?
    private(set) var phase = Phase.idle

    mutating func begin(_ trigger: Trigger) -> UUID? {
        guard phase == .idle else { return nil }
        let token = UUID()
        id = token; self.trigger = trigger; phase = .checking
        return token
    }
    func isCurrent(_ token: UUID) -> Bool { id == token && phase != .idle }
    mutating func show(_ token: UUID) -> Bool {
        guard isCurrent(token), phase == .checking else { return false }
        phase = .choosing; return true
    }
    mutating func release(_ source: Trigger, selection: UUID?) -> UUID? {
        guard trigger == source, phase == .checking || phase == .choosing else { return nil }
        guard phase == .choosing, selection != nil, let token = id else { cancel(); return nil }
        phase = .waitingForModifiers
        return token
    }
    mutating func commit(_ token: UUID) -> Bool {
        guard isCurrent(token), phase == .waitingForModifiers else { return false }
        phase = .inserting; return true
    }
    mutating func cancel() { id = nil; trigger = nil; phase = .idle }
}

@MainActor
func waitForModifierRelease(timeout: Duration = HoldMenuSession.modifierReleaseTimeout,
                            released: () -> Bool, current: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !released() {
        guard !Task.isCancelled, current(), clock.now < deadline else { return false }
        do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
    }
    return !Task.isCancelled && current()
}

struct ApplicationIdentity: Codable, Hashable, Sendable {
    var bundleIdentifier: String?
    var fallbackBundlePath: String?
    var key: String {
        if let id = bundleIdentifier, !id.isEmpty { return "bundle:\(id)" }
        return "path:\(URL(fileURLWithPath: fallbackBundlePath ?? "").standardizedFileURL.resolvingSymlinksInPath().path)"
    }
}

struct Snippet: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var text: String
    var isEnabled = true
}

func floatingButtonTitle(_ title: String) -> String {
    String(title.prefix(4)) + (title.count > 4 ? "…" : "")
}

struct AppProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var application: ApplicationIdentity
    var displayName: String
    var lastKnownBundlePath: String?
    var isEnabled = true
    var displayMode = DisplayMode.modifierClick
    var buttons: [Snippet] = []

    func canTrigger(_ source: HoldMenuSession.Trigger) -> Bool {
        guard isEnabled, buttons.contains(where: \.isEnabled) else { return false }
        switch displayMode {
        case .modifierClick: return source == .modifier
        case .shortcutOnly: return source == .shortcut
        }
    }
}

enum MenuAnchorMode: String, Codable, CaseIterable, Sendable {
    case mouse, caret
    var title: String { self == .mouse ? "鼠标位置" : "输入光标位置" }
}

struct AuthorizationFlow {
    enum Step: Equatable {
        case authorize, restart, ready, reauthorize
        var title: String {
            switch self {
            case .authorize: "授权"
            case .restart: "重启"
            case .ready: "已就绪"
            case .reauthorize: "重新授权"
            }
        }
    }
    private(set) var step: Step = .authorize
    private var previousTrusted: Bool?
    private var restartRequired = false
    private let afterRestart: Bool
    init(afterRestart: Bool = false) { self.afterRestart = afterRestart }
    mutating func refresh(accessibility: Bool, paste: Bool) {
        if previousTrusted == false && accessibility { restartRequired = true }
        previousTrusted = accessibility
        if !accessibility { restartRequired = false; step = .authorize }
        else if restartRequired { step = .restart }
        else if paste { step = .ready }
        else { step = afterRestart ? .reauthorize : .restart }
    }
}

struct Preferences: Codable, Equatable, Sendable {
    var isEnabled = true
    var clickModifier = ClickModifier.option
    var menuAnchorMode = MenuAnchorMode.mouse
    init() { }
    private enum CodingKeys: String, CodingKey { case isEnabled, clickModifier, menuAnchorMode }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        clickModifier = try values.decode(ClickModifier.self, forKey: .clickModifier)
        menuAnchorMode = try values.decodeIfPresent(MenuAnchorMode.self, forKey: .menuAnchorMode) ?? .mouse
    }
}

struct AppEntryVisibility: Equatable {
    private(set) var dock: Bool
    private(set) var menuBar: Bool

    static let dockKey = "PhrasePerch.dockIconVisible"
    static let menuBarKey = "PhrasePerch.menuBarIconVisible"

    init(dock: Bool = false, menuBar: Bool = true) {
        self.dock = dock
        self.menuBar = menuBar || !dock
    }

    mutating func setDock(_ visible: Bool) {
        guard visible || menuBar else { return }
        dock = visible
    }

    mutating func setMenuBar(_ visible: Bool) {
        guard visible || dock else { return }
        menuBar = visible
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.register(defaults: [dockKey: false, menuBarKey: true])
        return Self(dock: defaults.bool(forKey: dockKey), menuBar: defaults.bool(forKey: menuBarKey))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(dock, forKey: Self.dockKey)
        defaults.set(menuBar, forKey: Self.menuBarKey)
    }
}

func dockPolicyChangeNeeded(currentDockVisible: Bool, requestedDockVisible: Bool) -> Bool {
    currentDockVisible != requestedDockVisible
}

struct AppConfiguration: Codable, Equatable, Sendable {
    var schemaVersion = 2
    var profiles: [AppProfile] = []
    var preferences = Preferences()

    func validate() throws {
        guard schemaVersion == 2 else { throw InputFailure("不支持配置版本 \(schemaVersion)") }
        var identities = Set<String>()
        var ids = Set<UUID>()
        for profile in profiles {
            let identity = profile.application
            guard !(identity.bundleIdentifier ?? "").isEmpty || !(identity.fallbackBundlePath ?? "").isEmpty else {
                throw InputFailure("应用缺少身份")
            }
            guard identities.insert(identity.key).inserted, ids.insert(profile.id).inserted else {
                throw InputFailure("配置存在重复应用身份或 ID")
            }
            guard !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InputFailure("应用名称不能为空")
            }
            for button in profile.buttons {
                guard ids.insert(button.id).inserted else { throw InputFailure("按钮 ID 重复") }
                try validateSnippet(button)
            }
        }
    }
}

struct InputFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func validateSnippet(_ snippet: Snippet) throws {
    if let message = snippetTitleIssue(snippet.title) ?? snippetTextIssue(snippet.text) {
        throw InputFailure(message)
    }
}

func snippetTitleIssue(_ title: String) -> String? {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "请填写文案标题" : nil
}

func snippetTextIssue(_ text: String) -> String? {
    if text.isEmpty { return "请填写文案正文" }
    if text.utf8.count > 64 * 1024 { return "正文超过 64 KiB，请缩短内容" }
    if text.unicodeScalars.contains(where: { scalar in
        (scalar.value < 32 && ![9, 10, 13].contains(scalar.value)) || (127...159).contains(scalar.value)
    }) { return "正文含不支持的控制字符" }
    return nil
}

func verifyInsertion(before: String, range: NSRange, text: String, after: String) -> InsertionResult? {
    let original = before as NSString
    guard range.location <= original.length, range.length <= original.length - range.location else { return nil }
    if after == original.replacingCharacters(in: range, with: text) { return .insertedVerified }
    let prefix = original.substring(to: range.location)
    let suffix = original.substring(from: range.location + range.length)
    let result = after as NSString
    let prefixLength = (prefix as NSString).length, suffixLength = (suffix as NSString).length
    guard after.hasPrefix(prefix), after.hasSuffix(suffix), result.length >= prefixLength + suffixLength else { return nil }
    let inserted = result.substring(with: NSRange(location: prefixLength, length: result.length - prefixLength - suffixLength))
    if !inserted.isEmpty, inserted != text, text.hasPrefix(inserted) { return .partialVerified }
    return nil
}

func flippedScreenPoint(_ point: CGPoint, primaryScreenTop: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: primaryScreenTop - point.y)
}

// ponytail: one operation globally; independent concurrent destinations are outside this MVP.
struct OperationGate {
    private(set) var activeID: UUID?
    private(set) var generation = 0
    private(set) var mayHaveMutated = false
    mutating func begin() -> UUID? {
        guard activeID == nil else { return nil }
        let id = UUID(); activeID = id; mayHaveMutated = false
        return id
    }
    mutating func invalidate() { generation += 1 }
    func isCurrent(_ id: UUID, generation expected: Int) -> Bool {
        activeID == id && generation == expected
    }
    mutating func markWriting(_ id: UUID) { if activeID == id { mayHaveMutated = true } }
    mutating func finish(_ id: UUID) { if activeID == id { activeID = nil } }
}

enum InsertionResult: String, Sendable {
    case insertedVerified, dispatchedUnverified, notWritten, unsupported
    case interruptedAfterDispatch, partialVerified, indeterminate
    var closesMenu: Bool { self == .insertedVerified || self == .dispatchedUnverified }
    var message: String {
        switch self {
        case .insertedVerified: "已插入"
        case .dispatchedUnverified: "粘贴操作已发送，请检查目标应用。"
        case .notWritten: "未写入，请先将光标放到可输入位置"
        case .unsupported: "当前输入位置暂不支持"
        case .interruptedAfterDispatch: "输入已停止，请检查已输入内容"
        case .partialVerified: "已插入部分内容，请检查"
        case .indeterminate: "无法确认输入结果，请检查"
        }
    }
}
