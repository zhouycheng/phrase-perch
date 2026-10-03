import Foundation

@testable import PhrasePerch

@MainActor
final class ManualAnimationScheduler: AnimationScheduling {
    private(set) var durations: [TimeInterval] = []
    private var completions: [@MainActor () -> Void] = []
    func schedule(after duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        durations.append(duration)
        completions.append(completion)
    }
    func finish(_ index: Int) { completions[index]() }
}
