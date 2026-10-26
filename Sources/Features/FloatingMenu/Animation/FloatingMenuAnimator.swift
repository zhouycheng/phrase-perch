import AppKit
import QuartzCore

@MainActor
final class FloatingMenuAnimator {
    let configuration: FloatingMenuAnimationConfiguration
    private let scheduler: any AnimationScheduling
    private let reduceMotion: @MainActor () -> Bool
    private var generation = 0
    init(
        configuration: FloatingMenuAnimationConfiguration = FloatingMenuAnimationConfiguration(),
        scheduler: any AnimationScheduling = MainQueueAnimationScheduler(),
        reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.configuration = configuration
        self.scheduler = scheduler
        self.reduceMotion = reduceMotion
    }
    func cancel() { generation += 1 }
    func animate(
        layer: CALayer?, layout: RadialLayout, expanding: Bool,
        direction: FloatingMenuAnimationConfiguration.Direction = .forward, completion: @escaping @MainActor () -> Void
    ) {
        let reduced = reduceMotion()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let layer {
            var collapsed = transform(layer: layer, layout: layout, scale: configuration.collapsedScale,
                angle: 0, remainingTravel: 1)
            if reduced { collapsed = CATransform3DIdentity }
            // Keep AppKit's layer position untouched. Transform and opacity share one clock.
            let shown = layer.animation(forKey: "radialMotion") == nil ? layer : (layer.presentation() ?? layer)
            let current = shown.transform
            let opacity = shown.opacity
            let destination = expanding ? CATransform3DIdentity : collapsed
            layer.removeAllAnimations()
            layer.transform = destination
            layer.opacity = expanding ? 1 : 0
            let group = CAAnimationGroup()
            if expanding && !reduced {
                group.animations = expansion(layer: layer, layout: layout, direction: direction)
                group.timingFunction = CAMediaTimingFunction(name: .linear)
            } else {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = expanding ? 0 : opacity
                fade.toValue = expanding ? 1 : 0
                group.animations = [fade]
                if !reduced {
                    let motion = CABasicAnimation(keyPath: "transform")
                    motion.fromValue = NSValue(caTransform3D: current)
                    motion.toValue = NSValue(caTransform3D: destination)
                    group.animations?.append(motion)
                }
                group.timingFunction = CAMediaTimingFunction(
                    controlPoints: configuration.timingCurve.x, configuration.timingCurve.y,
                    configuration.timingCurve.z, configuration.timingCurve.w)
            }
            group.duration = configuration.duration(expanding: expanding, reduced: reduced)
            layer.add(group, forKey: "radialMotion")
        }
        CATransaction.commit()
        generation += 1
        let token = generation
        scheduler.schedule(after: configuration.duration(expanding: expanding, reduced: reduced)) { [weak self, weak layer] in
            guard let self, generation == token else { return }
            layer?.removeAnimation(forKey: "radialMotion")
            completion()
        }
    }

    private func transform(layer: CALayer, layout: RadialLayout, scale: CGFloat,
        angle: CGFloat, remainingTravel: CGFloat) -> CATransform3D {
        let pivot = CGPoint(x: layout.localCenter.x - layer.bounds.minX - layer.anchorPoint.x * layer.bounds.width,
            y: layout.localCenter.y - layer.bounds.minY - layer.anchorPoint.y * layer.bounds.height)
        var value = CATransform3DMakeAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: scale, y: scale))
        // Encode the pivot in the transform; AppKit owns the backing layer's anchor and position.
        value.m41 = pivot.x - value.m11 * pivot.x - value.m21 * pivot.y
            + (layout.anchor.x - layout.center.x) * remainingTravel
        value.m42 = pivot.y - value.m12 * pivot.x - value.m22 * pivot.y
            + (layout.anchor.y - layout.center.y) * remainingTravel
        return value
    }

    private func expansion(layer: CALayer, layout: RadialLayout, direction: FloatingMenuAnimationConfiguration.Direction) -> [CAAnimation] {
        let times = [0.0, 0.69, 0.84, 1.0]
        // AppKit's upward Y axis reverses the preview's CSS rotation signs.
        let sign: CGFloat = direction == .forward ? 1 : -1
        let angles: [CGFloat] = [55 * .pi / 180 * sign, 0, -3 * .pi / 180 * sign, 0]
        let scales: [CGFloat] = [configuration.collapsedScale, 1, FloatingMenuAnimationConfiguration.peakScale, 1]
        let curves: [SIMD4<Double>] = [SIMD4(0.2, 0.7, 0.2, 1), SIMD4(0.3, 0, 0.6, 1), SIMD4(0.2, 0.6, 0.3, 1)]
        var keyTimes: [NSNumber] = []
        var transforms: [NSValue] = []
        var opacities: [CGFloat] = []
        for segment in 0..<3 {
            let steps = max(1, Int(ceil((times[segment + 1] - times[segment]) * configuration.expandDuration * 120)))
            for step in 0..<steps {
                let progress = Double(step) / Double(steps)
                let eased = CGFloat(ease(progress, curve: curves[segment]))
                keyTimes.append(NSNumber(value: times[segment] + (times[segment + 1] - times[segment]) * progress))
                transforms.append(NSValue(caTransform3D: transform(layer: layer, layout: layout,
                    scale: scales[segment] + (scales[segment + 1] - scales[segment]) * eased,
                    angle: angles[segment] + (angles[segment + 1] - angles[segment]) * eased,
                    remainingTravel: segment == 0 ? 1 - eased : 0)))
                opacities.append(segment == 0 ? eased : 1)
            }
        }
        keyTimes.append(1)
        transforms.append(NSValue(caTransform3D: CATransform3DIdentity))
        opacities.append(1)
        let motion = CAKeyframeAnimation(keyPath: "transform")
        motion.values = transforms
        motion.keyTimes = keyTimes
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacities
        fade.keyTimes = keyTimes
        return [motion, fade]
    }

    private func ease(_ progress: Double, curve: SIMD4<Double>) -> Double {
        guard progress > 0, progress < 1 else { return progress }
        func coordinate(_ t: Double, _ first: Double, _ second: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * first + 3 * (1 - t) * t * t * second + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<18 {
            let middle = (low + high) / 2
            if coordinate(middle, curve.x, curve.z) < progress { low = middle } else { high = middle }
        }
        return coordinate((low + high) / 2, curve.y, curve.w)
    }
}
