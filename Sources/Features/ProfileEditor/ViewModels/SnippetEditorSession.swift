import AppKit
import KeyboardShortcuts
import SwiftUI

struct SnippetEditorSession: Equatable {
    static let pageSize = 8
    var selectedID: UUID?
    var page = 0

    static func pageCount(_ count: Int) -> Int { max(1, (count + pageSize - 1) / pageSize) }

    mutating func select(_ id: UUID?, in ids: [UUID]) {
        selectedID = id
        reconcile(ids)
    }
    mutating func showPage(_ requested: Int, in ids: [UUID]) {
        page = min(max(0, requested), Self.pageCount(ids.count) - 1)
        selectedID = ids.isEmpty ? nil : ids[page * Self.pageSize]
    }
    mutating func reconcile(_ ids: [UUID]) {
        page = min(max(0, page), Self.pageCount(ids.count) - 1)
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            page = index / Self.pageSize
        } else {
            selectedID = ids.isEmpty ? nil : ids[page * Self.pageSize]
        }
    }
    mutating func deleted(at index: Int, remaining ids: [UUID]) {
        select(ids.isEmpty ? nil : ids[min(index, ids.count - 1)], in: ids)
    }
}
