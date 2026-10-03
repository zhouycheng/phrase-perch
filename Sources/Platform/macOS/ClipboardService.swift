import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

enum ClipboardService {
    @MainActor
    static func copy(_ text: String, pasteboard: NSPasteboard = .general) throws -> Int {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw InputFailure("剪贴板写入失败，未粘贴") }
        return pasteboard.changeCount
    }
}
