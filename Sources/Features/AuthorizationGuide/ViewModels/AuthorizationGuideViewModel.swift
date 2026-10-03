import Foundation
import Observation

@MainActor @Observable
final class AuthorizationGuideViewModel {
    private(set) var applicationURL: URL?
    private(set) var isVisible = false
    func show(applicationURL: URL) {
        self.applicationURL = applicationURL
        isVisible = true
    }
    func hide() { isVisible = false }
    func didDrag(accepted: Bool) { if accepted { hide() } }
}
