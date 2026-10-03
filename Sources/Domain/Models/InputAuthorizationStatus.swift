import CoreGraphics
import Foundation

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
