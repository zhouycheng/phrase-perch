import Foundation

@MainActor
protocol AnimationScheduling {
    func schedule(after duration: TimeInterval, completion: @escaping @MainActor () -> Void)
}
