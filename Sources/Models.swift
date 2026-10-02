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

struct ModifierGesture: Sendable {
    let modifier: ClickModifier
    private(set) var valid = true
    var dragged = false

    init(modifier: ClickModifier, flags: UInt) {
        self.modifier = modifier
        observe(flags: flags)
    }
    mutating func observe(flags: UInt) {
        let relevant = UInt(CGEventFlags([.maskCommand, .maskShift, .maskAlternate, .maskControl]).rawValue)
        valid = valid && flags & relevant == modifier.mask
    }
    func acceptsEditor(sameEditor: Bool, selectionLength: Int?) -> Bool {
        valid && sameEditor && (!dragged || (selectionLength ?? 0) > 0)
    }
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

struct AppProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var application: ApplicationIdentity
    var displayName: String
    var lastKnownBundlePath: String?
    var isEnabled = true
    var displayMode = DisplayMode.modifierClick
    var buttons: [Snippet] = []
}

struct Preferences: Codable, Equatable, Sendable {
    var isEnabled = true
    var clickModifier = ClickModifier.option
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
    guard !snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InputFailure("按钮名称不能为空") }
    guard !snippet.text.isEmpty else { throw InputFailure("正文不能为空") }
    guard snippet.text.utf8.count <= 64 * 1024 else { throw InputFailure("正文超过 64 KiB") }
    guard !snippet.text.unicodeScalars.contains(where: { scalar in
        (scalar.value < 32 && ![9, 10, 13].contains(scalar.value)) || (127...159).contains(scalar.value)
    }) else { throw InputFailure("正文含不支持的控制字符") }
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
        case .dispatchedUnverified: "已发送输入，请查看目标应用"
        case .notWritten: "未写入，请先将光标放到可输入位置"
        case .unsupported: "当前输入位置暂不支持"
        case .interruptedAfterDispatch: "输入已停止，请检查已输入内容"
        case .partialVerified: "已插入部分内容，请检查"
        case .indeterminate: "无法确认输入结果，请检查"
        }
    }
}
