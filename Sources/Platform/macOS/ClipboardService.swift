import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

enum ClipboardService {
    @MainActor
    static func fileURLs(pasteboard: NSPasteboard = .general) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    @MainActor
    static func copyFile(_ file: ClipboardFile, pasteboard: NSPasteboard = .general) throws -> Int {
        guard FileManager.default.isReadableFile(atPath: file.url.path) else { throw InputFailure("附件文件不可用") }
        let item = NSPasteboardItem()
        guard item.setString(file.url.absoluteString, forType: .fileURL) else { throw InputFailure("附件剪贴板准备失败") }
        if let type = file.imageType, let data = file.imageData {
            guard item.setData(data, forType: NSPasteboard.PasteboardType(type)) else { throw InputFailure("图片剪贴板准备失败") }
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw InputFailure("附件剪贴板写入失败，未粘贴") }
        return pasteboard.changeCount
    }
    @MainActor
    static func copy(_ text: String, pasteboard: NSPasteboard = .general) throws -> Int {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw InputFailure("剪贴板写入失败，未粘贴") }
        return pasteboard.changeCount
    }
}
