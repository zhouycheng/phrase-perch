import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

@MainActor
final class StubPasteSystem {
    var isCurrent = true
    var released = true
    var authorized = true
    var clipboardChanged = false
    var canDispatch = true
    var copies: [String] = []
    var dispatches = 0
    var revision = 0
    var environment: PasteEnvironment {
        PasteEnvironment(
            targetIsCurrent: { _ in self.isCurrent }, modifiersReleased: { self.released },
            authorized: { self.authorized },
            copy: { text in
                self.copies.append(text)
                self.revision += 1
                return self.revision
            }, clipboardRevision: { self.revision + (self.clipboardChanged ? 1 : 0) },
            dispatch: {
                guard self.canDispatch else { return false }
                self.dispatches += 1
                return true
            })
    }
}
