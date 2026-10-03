import AppKit
import KeyboardShortcuts
import SwiftUI

struct SnippetDeletion {
    private(set) var id: UUID?
    mutating func request(_ id: UUID) { self.id = id }
    mutating func cancel() { id = nil }
    mutating func confirm(_ confirmedID: UUID, profile: inout AppProfile, session: inout SnippetEditorSession) {
        defer { id = nil }
        guard let index = profile.buttons.firstIndex(where: { $0.id == confirmedID }) else { return }
        profile.buttons.remove(at: index)
        session.deleted(at: index, remaining: profile.buttons.map(\.id))
    }
}
