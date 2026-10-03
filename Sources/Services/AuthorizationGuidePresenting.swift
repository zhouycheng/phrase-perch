import Foundation

@MainActor
protocol AuthorizationGuidePresenting: AnyObject {
    var isVisible: Bool { get }
    var onDragEnded: ((Bool) -> Void)? { get set }
    func show(applicationURL: URL)
    func hide()
}
