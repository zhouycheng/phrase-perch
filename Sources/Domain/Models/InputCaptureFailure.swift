import Foundation

enum InputCaptureFailure: Error, LocalizedError, Equatable {
    case authorization, secureInput, changed, unavailable(Int32)
    var errorDescription: String? {
        switch self {
        case .authorization: "辅助功能权限未就绪，请在设置中授权当前应用。"
        case .secureInput: "当前处于安全输入状态，已取消操作。"
        case .changed: "输入焦点或选区已变化，请重新触发。"
        case .unavailable(let code): "输入位置读取失败（AX \(code)），请重试。"
        }
    }
}
