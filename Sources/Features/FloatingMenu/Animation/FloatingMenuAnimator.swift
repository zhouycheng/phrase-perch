import AppKit
import QuartzCore

@MainActor
final class FloatingMenuAnimator {
    let configuration: FloatingMenuAnimationConfiguration
    private let scheduler: any AnimationScheduling
    private var generation = 0
    init(
        configuration: FloatingMenuAnimationConfiguration = FloatingMenuAnimationConfiguration(),
        scheduler: any AnimationScheduling = MainQueueAnimationScheduler()
    ) {
        self.configuration = configuration
        self.scheduler = scheduler
    }
    func cancel() { generation += 1 }
    func animate(
        buttons: [NSButton], layout: RadialLayout, expanding: Bool, completion: @escaping @MainActor () -> Void
    ) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for button in buttons {
            guard let layer = button.layer else { continue }
            var collapsed = CATransform3DMakeScale(configuration.collapsedScale, configuration.collapsedScale, 1)
            collapsed.m41 = layout.localAnchor.x - button.frame.midX
            collapsed.m42 = layout.localAnchor.y - button.frame.midY
            if reduced { collapsed = CATransform3DIdentity }
            // Keep AppKit's layer position untouched. Transform and opacity share one clock.
            let current = layer.presentation()?.transform ?? layer.transform
            let opacity = layer.presentation()?.opacity ?? layer.opacity
            let destination = expanding ? CATransform3DIdentity : collapsed
            layer.removeAllAnimations()
            layer.transform = destination
            layer.opacity = expanding ? 1 : 0
            let motion = CABasicAnimation(keyPath: "transform")
            motion.fromValue = NSValue(caTransform3D: expanding ? collapsed : current)
            motion.toValue = NSValue(caTransform3D: destination)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = expanding ? 0 : opacity
            fade.toValue = expanding ? 1 : 0
            let group = CAAnimationGroup()
            group.animations = [motion, fade]
            group.duration = configuration.duration(expanding: expanding, reduced: reduced)
            group.timingFunction = CAMediaTimingFunction(
                controlPoints: configuration.timingCurve.x, configuration.timingCurve.y,
                configuration.timingCurve.z, configuration.timingCurve.w)
            layer.add(group, forKey: "radialMotion")
        }
        CATransaction.commit()
        generation += 1
        let token = generation
        scheduler.schedule(after: configuration.duration(expanding: expanding, reduced: reduced)) { [weak self] in
            guard let self, generation == token else { return }
            completion()
        }
    }
}
