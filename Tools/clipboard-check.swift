import AppKit
import CryptoKit
import Foundation
let pasteboard = NSPasteboard.general
let items = (pasteboard.pasteboardItems ?? []).map { item in
 Dictionary(uniqueKeysWithValues: item.types.map { type in
  (type.rawValue, item.data(forType: type).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "unavailable")
 })
}
let data = try JSONSerialization.data(withJSONObject: ["changeCount": pasteboard.changeCount, "items": items], options: [.sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"), clipboardChangeCount=\(pasteboard.changeCount)")
