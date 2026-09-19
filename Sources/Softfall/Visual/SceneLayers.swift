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
    private let lightning = LightningLayer()
    private let flash = CAGradientLayer()
    private var size: CGSize = .zero
    private var scale: CGFloat = 2
    private var embersWereOff = true
    /// The gust running ahead of a strike: when it began, how hard, which way.
    private var gustStart: CFTimeInterval = -1
    private var gustPeak: CGFloat = 0
    private var gustHold: CFTimeInterval = 0
    /// The overlay fades to the user's visibility setting; a scene that lives
    /// inside a window of its own wants to be seen in full. Set once by the
    /// owner, never by state.
    var opacityOverride: Float?
    /// Multiplies the ember birth rate. The overlay leaves it at 1; a small
    /// close-up view wants more of them than its area alone would earn.
    var emberScale: Float = 1

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

        // The sheet of light sits under the bolt, so the bolt stays legible
        // against its own flash. It is a radial bloom from wherever the bolt
        // left the cloud: blue-white at the source, yellow across the rest of
        // the sky, gone at the edges — a flat wash lit the whole desktop like
        // a camera flash.
        flash.frame = CGRect(origin: .zero, size: size)
        flash.type = .radial
        flash.colors = [
            NSColor(calibratedRed: 0.75, green: 0.87, blue: 1.00, alpha: 1.00).cgColor,
            NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.51, alpha: 0.55).cgColor,
            NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.31, alpha: 0.25).cgColor,
            NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.24, alpha: 0.00).cgColor
        ]
        flash.locations = [0, 0.28, 0.6, 1.0]
        flash.opacity = 0
        flash.isHidden = true
        flash.actions = ["startPoint": NSNull(), "endPoint": NSNull(), "hidden": NSNull()]
        root.addSublayer(flash)

        root.addSublayer(lightning)
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
        let wander = CGFloat((a * 0.62 + b * 0.38) * 0.34)
        return max(-0.6, min(0.6, wander + gust(at: t)))
    }

    /// The transient a strike adds to the wind: up in a quarter second, held
    /// until the flash, then let go over a second and a half. Smoothstep on
    /// both ends — a gust that snaps on reads as a bug, not weather.
    private func gust(at t: CFTimeInterval) -> CGFloat {
        guard gustStart >= 0 else { return 0 }
        let elapsed = t - gustStart
        let rise = 0.25, release = 1.5
        let shape: CGFloat
        if elapsed < rise {
            shape = smoothstep(elapsed / rise)
        } else if elapsed < gustHold {
            shape = 1
        } else if elapsed < gustHold + release {
            shape = 1 - smoothstep((elapsed - gustHold) / release)
        } else {
            gustStart = -1
            return 0
        }
        return gustPeak * shape
    }

    private func smoothstep(_ x: Double) -> CGFloat {
        let c = min(max(x, 0), 1)
        return CGFloat(c * c * (3 - 2 * c))
    }

    /// The front arrives before the strike does.
    func gust(_ strike: LightningStrike) {
        guard strike.gustLead > 0 else { return }
        gustStart = CACurrentMediaTime()
        gustHold = strike.gustLead
        gustPeak = CGFloat(strike.gustStrength * strike.gustDirection) * 0.5
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

        let target = opacityOverride ?? Float(state.isPlaying ? state.opacity : 0)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.7)
        root.opacity = target
        atmosphere.opacity = wash
        CATransaction.commit()
    }

    private func updateEmbers(state: MixState) {
        let density = state.effectiveDensity(.embers)
        let areaScale = Float(max(size.width / 1920.0, 0.6))
        let rate = Float(density * 85) * areaScale * emberScale

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
    func flashLightning(_ strike: LightningStrike, opacityScale: Double) {
        let d = strike.distance

        // The bolt and the sheet of light are one event, so they are fired
        // together. The bolt decides for itself whether there is anything to
        // draw — a strike behind cloud is bloom only.
        let origin = lightning.strike(strike, opacityScale: opacityScale, in: size, scale: scale)

        let peak = Float(lerp(0.42, 0.10, d) * opacityScale)
        guard peak > 0.005 else { return }

        // Bloom from the bolt's root when there is one; from somewhere along
        // the top edge when the strike is behind cloud.
        let x = origin.map { $0.x / size.width } ?? CGFloat.random(in: 0.2...0.8)
        let radius = 0.9 * max(size.width, size.height)
        flash.startPoint = CGPoint(x: x, y: 1.0)
        flash.endPoint = CGPoint(x: x + radius / size.width, y: 1.0 - radius / size.height)

        flash.isHidden = false
        flash.removeAllAnimations()

        // The sky lights on the strike's own strokes — the same list the bolt
        // flickers to and the thunder cracks to. A faint lift while the
        // leader creeps down, a jump on each return stroke, a slow fade after
        // the last. A crawler lights the sky more gently than a bolt.
        let stroke = strike.kind == .crawler ? 0.6 : 1.0
        var keyframes: [(time: Double, value: Float)] = [(0, 0)]
        if strike.leaderDuration > 0 {
            keyframes.append((strike.leaderDuration - 0.004, peak * 0.08))
        }
        for s in strike.strokes {
            let v = peak * Float(s.strength * stroke)
            keyframes.append((s.time, v))
            keyframes.append((s.time + 0.03, v * 0.35))
            keyframes.append((s.time + 0.06, v * 0.15))
        }
        let last = strike.strokes.last?.time ?? 0
        keyframes.append((last + 0.35, peak * 0.06))
        keyframes.append((strike.duration + d * 0.4, 0))

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.duration = strike.duration + d * 0.4
        animation.values = keyframes.map { $0.value }
        animation.keyTimes = keyframes.map { NSNumber(value: min(max($0.time / animation.duration, 0), 1)) }
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = true
        flash.add(animation, forKey: "flash")

        rain.lightUp()
    }

    func resize(to newSize: CGSize, scale newScale: CGFloat) {
        guard newSize != size || newScale != scale else { return }
        build(size: newSize, scale: newScale)
    }
}
