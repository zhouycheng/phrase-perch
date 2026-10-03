import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

struct PreparedInput: Sendable {
    var before: String?
    var selection: NSRange?
}
