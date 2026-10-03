import CoreGraphics
import Foundation

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
