import Foundation

@MainActor
struct MainQueueAnimationScheduler: AnimationScheduling {
    func schedule(after duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { completion() }
    }
}
