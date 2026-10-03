import Darwin
import SwiftUI
import XCTest

@testable import PhrasePerch

@MainActor
final class StubAuthorizationGuide: AuthorizationGuidePresenting {
    var isVisible = false
    var onDragEnded: ((Bool) -> Void)?
    func show(applicationURL: URL) { isVisible = true }
    func hide() { isVisible = false }
}
