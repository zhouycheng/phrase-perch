import CoreGraphics
import Foundation

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
        if !accessibility {
            restartRequired = false
            step = .authorize
        } else if restartRequired {
            step = .restart
        } else if paste {
            step = .ready
        } else {
            step = afterRestart ? .reauthorize : .restart
        }
    }
}
