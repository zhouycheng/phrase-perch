import CoreGraphics
import Foundation

struct InputFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
