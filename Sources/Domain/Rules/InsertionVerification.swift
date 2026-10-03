import CoreGraphics
import Foundation

func verifyInsertion(before: String, range: NSRange, text: String, after: String) -> InsertionResult? {
    let original = before as NSString
    guard range.location <= original.length, range.length <= original.length - range.location else { return nil }
    if after == original.replacingCharacters(in: range, with: text) { return .insertedVerified }
    let prefix = original.substring(to: range.location)
    let suffix = original.substring(from: range.location + range.length)
    let result = after as NSString
    let prefixLength = (prefix as NSString).length
    let suffixLength = (suffix as NSString).length
    guard after.hasPrefix(prefix), after.hasSuffix(suffix), result.length >= prefixLength + suffixLength else {
        return nil
    }
    let inserted = result.substring(
        with: NSRange(location: prefixLength, length: result.length - prefixLength - suffixLength))
    if !inserted.isEmpty, inserted != text, text.hasPrefix(inserted) { return .partialVerified }
    return nil
}
