import AppKit
import QuartzCore

/// Builds and drives everything drawn on one display.
///
/// Rain is a hand-drawn layer (`RainLayer`) stepped by a display link. Embers
/// stay on `CAEmitterLayer`: an ember is a round glow with no direction of
/// travel to face, so none of the reasons rain had to leave the emitter apply
/// to it, and an emitter animates itself for free.
///
/// Two things make rain read over an arbitrary desktop wallpaper rather than
/// dissolving into it: a faint atmosphere wash for it to be bright against,
/// and depth bands — far drops small, slow and faint, near ones long, fast
/// and nearly opaque.
final class SceneLayers {

    let root = CALayer()
    private let atmosphere = CAGradientLayer()
    private let rain = RainLayer()
    private let embers = CAEmitterLayer()
    private let flash = CALayer()
    private var size: CGSize = .zero
    private var scale: CGFloat = 2
    private var embersWereOff = true

    /// Overall drop opacity, dialled in against a real desktop rather than
    /// guessed. How blue the rain is comes from the mix state instead — that
    /// one has to be judged against the wallpaper it will sit on.
    private static let dropOpacity: CGFloat = 0.55

    // MARK: Build

    func build(size: CGSize, scale: CGFloat) {
        self.size = size
        self.scale = scale
        root.frame = CGRect(origin: .zero, size: size)
        root.masksToBounds = true
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        embersWereOff = true

        atmosphere.frame = CGRect(origin: .zero, size: size)
        atmosphere.colors = [
            NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.11, alpha: 1.00).cgColor,
            NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.13, alpha: 0.30).cgColor
        ]
        // Unit space here has its origin at the bottom-left, so y = 1 is the
        // top of the screen — which is where an overcast sky is darkest.
        atmosphere.startPoint = CGPoint(x: 0.5, y: 1.0)
        atmosphere.endPoint = CGPoint(x: 0.5, y: 0.0)
        atmosphere.opacity = 0
        root.addSublayer(atmosphere)

        rain.configure(size: size, scale: scale)
        rain.isHidden = true
        root.addSublayer(rain)

        buildEmbers(size: size)
        root.addSublayer(embers)

        flash.frame = CGRect(origin: .zero, size: size)
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        flash.isHidden = true
        root.addSublayer(flash)
    }

    private func buildEmbers(size: CGSize) {
        embers.frame = CGRect(origin: .zero, size: size)
        embers.renderMode = .additive
        embers.isHidden = true
        embers.emitterShape = .line
        embers.emitterPosition = CGPoint(x: size.width / 2, y: -20)
        embers.emitterSize = CGSize(width: size.width * 0.9, height: 1)

        let cell = CAEmitterCell()
        cell.name = "embers"
        cell.birthRate = 0
        cell.contents = ParticleTextures.ember
        cell.velocity = 95
        cell.velocityRange = 55
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = 0.5
        cell.yAcceleration = 26
        cell.xAcceleration = 8
        cell.lifetime = 7
        cell.lifetimeRange = 3
        cell.scale = 0.42
        cell.scaleRange = 0.3
        cell.scaleSpeed = -0.035
        cell.alphaSpeed = -0.16
        cell.spin = 0.6
        cell.spinRange = 1.4
        cell.color = NSColor(calibratedRed: 1.0, green: 0.60, blue: 0.24, alpha: 0.95).cgColor
        embers.emitterCells = [cell]
    }

    // MARK: Drive

    /// A slow wander, from two sine waves whose periods do not divide into one
    /// another. Rain that always falls at the same angle looks printed on; a
    /// wind slider would be one more thing to fiddle with, so it drifts by
    /// itself instead.
    ///
    /// This is now sampled every frame rather than only when a setting changes,
    /// so the angle actually moves while you watch it.
    private func autoWind() -> CGFloat {
        let t = CACurrentMediaTime()
        let a = sin(t * 0.037)
        let b = sin(t * 0.0113 + 1.7)
        return CGFloat((a * 0.62 + b * 0.38) * 0.34)
    }

    /// Called from the display link. Allocation-free except for the drop
    /// array's own growth, which settles within a second of a level change.
    func advance(dt: CGFloat) {
        guard !rain.isHidden else { return }
        rain.params.wind = autoWind()
        rain.advance(dt: dt)
    }

    /// Whether the display link still has anything to draw. Splashes outlive
    /// the drop that made them, so rain that has just been switched off is
    /// owed a few more frames.
    var wantsAnimation: Bool {
        !rain.isHidden
    }

    func update(state: MixState) {
        guard size != .zero else { return }

        let rainDensity = CGFloat(state.effectiveDensity(.rain))
        rain.params.intensity = rainDensity
        rain.params.dropOpacity = Self.dropOpacity
        rain.params.blue = CGFloat(state.rainBlue)
        // Calm mode is meant to be gentler, not merely thinner: slower drops
        // covering less ground per frame are what reads as calm.
        rain.params.speed = state.calmMode ? 0.75 : 1.0
        // Switching rain off never hides the layer here: the renderer keeps
        // drawing until the last drop has landed, then hides itself.
        if rainDensity > 0.0001 { rain.isHidden = false }

        updateEmbers(state: state)

        // The wash follows whatever is on screen, weighted: rain wants more of
        // it than a campfire does. Capped low enough to read as an overcast
        // sky rather than a dimmed display.
        let wash = Float(min(0.26, max(state.effectiveDensity(.rain) * 0.38,
                                       state.effectiveDensity(.embers) * 0.26)))

        let target = Float(state.isPlaying ? state.opacity : 0)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.7)
        root.opacity = target
        atmosphere.opacity = wash
        CATransaction.commit()
    }

    private func updateEmbers(state: MixState) {
        let density = state.effectiveDensity(.embers)
        let areaScale = Float(max(size.width / 1920.0, 0.6))
        let rate = Float(density * 85) * areaScale

        guard rate > 0 else {
            embers.setValue(0, forKeyPath: "emitterCells.embers.birthRate")
            // Only on the transition to off, so an already-idle emitter does
            // not queue a block every time it is visited.
            if !embersWereOff {
                embersWereOff = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak embers] in
                    guard let embers else { return }
                    let current = embers.value(forKeyPath: "emitterCells.embers.birthRate") as? Float ?? 0
                    if current <= 0 { embers.isHidden = true }
                }
            }
            return
        }

        if embers.isHidden || embersWereOff {
            embers.isHidden = false
            // Pre-roll so the scene arrives already full, rather than filling
            // in from the bottom edge over several seconds.
            embers.beginTime = CACurrentMediaTime() - 4
        }
        embersWereOff = false
        embers.setValue(rate, forKeyPath: "emitterCells.embers.birthRate")
    }

    // MARK: Lightning

    /// Draws a flash. `distance` 0 is overhead, 1 is far off — it controls
    /// brightness and how sharp the flicker is, matching the thunder that will
    /// follow a moment later.
    func flashLightning(distance: Double, opacityScale: Double) {
        let d = min(max(distance, 0), 1)
        let peak = Float(lerp(0.40, 0.07, d) * opacityScale)
        guard peak > 0.005 else { return }

        flash.isHidden = false
        flash.removeAllAnimations()

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        if d < 0.45 {
            // Close strikes flicker — one short stroke, then the main one.
            animation.values = [0, peak * 0.55, peak * 0.1, peak, 0]
            animation.keyTimes = [0, 0.04, 0.10, 0.16, 1.0]
            animation.duration = lerp(0.55, 1.1, d)
        } else {
            // Distant sheet lightning: a soft bloom with no hard edge.
            animation.values = [0, peak, 0]
            animation.keyTimes = [0, 0.3, 1.0]
            animation.duration = lerp(1.1, 1.9, d)
        }
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.isRemovedOnCompletion = true
        flash.add(animation, forKey: "flash")
    }

    func resize(to newSize: CGSize, scale newScale: CGFloat) {
        guard newSize != size || newScale != scale else { return }
        build(size: newSize, scale: newScale)
    }
}
