import Foundation

struct PermissionRequirement: Identifiable, Equatable {
    enum Status: String {
        case notGranted = "未授权"
        case granted = "已授权"
        case pending = "授权待生效"
        case repair = "需要重新授权"
        case notRequired = "无需授权"
    }
    let id: String
    let title: String
    let purpose: String
    let status: Status
    let instructions: String
    let actionTitle: String?
    var needsAttention: Bool { status != .granted && status != .notRequired }
}
