import Foundation

struct FloatingMenuAnimationConfiguration: Equatable {
    let expandDuration: TimeInterval
    let collapseDuration: TimeInterval
    let reducedDuration: TimeInterval
    let collapsedScale: CGFloat
    let timingCurve: SIMD4<Float>

    init(
        expandDuration: TimeInterval = 0.18, collapseDuration: TimeInterval = 0.12,
        reducedDuration: TimeInterval = 0.08, collapsedScale: CGFloat = 0.2,
        timingCurve: SIMD4<Float> = SIMD4(0.16, 1, 0.3, 1)
    ) {
        self.expandDuration = expandDuration
        self.collapseDuration = collapseDuration
        self.reducedDuration = reducedDuration
        self.collapsedScale = collapsedScale
        self.timingCurve = timingCurve
    }
    func duration(expanding: Bool, reduced: Bool) -> TimeInterval {
        reduced ? reducedDuration : (expanding ? expandDuration : collapseDuration)
    }
}
