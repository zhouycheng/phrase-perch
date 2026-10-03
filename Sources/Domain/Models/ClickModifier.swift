import CoreGraphics
import Foundation

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
