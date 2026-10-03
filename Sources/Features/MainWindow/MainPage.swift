import AppKit
import KeyboardShortcuts
import SwiftUI

enum MainPage: CaseIterable {
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
