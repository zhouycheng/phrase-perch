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
        let node = MenuNode(kind: .snippet, id: confirmedID)
        let parent = profile.groups.first { $0.children.contains(node) }?.id
        profile.setChildren(profile.children(of: parent).filter { $0 != node }, of: parent)
        profile.buttons.remove(at: index)
        session.deleted(at: index, remaining: profile.buttons.map(\.id))
    }
}
