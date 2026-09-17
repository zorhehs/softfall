import AppKit
import QuartzCore

/// Builds and drives the Core Animation particle layers.
///
/// Two things make rain read over an arbitrary desktop wallpaper rather than
/// dissolving into it: a faint atmosphere wash for it to be bright against,
/// and depth bands — far drops small, slow and faint, near ones long, fast
/// and nearly opaque. Scaling one texture cannot do the second, because scale
/// stretches width and length together and a "near" drop just comes out fat.
final class SceneLayers {

    let root = CALayer()
    private let atmosphere = CAGradientLayer()
    private let flash = CALayer()
    private var emitters: [Layer: CAEmitterLayer] = [:]
    private var bands: [Layer: [Band]] = [:]
    private var size: CGSize = .zero
    private var lastDensities: [Layer: Double] = [:]

    /// Overall drop opacity, and how blue they are. Both were dialled in
    /// against a real desktop rather than guessed.
    private static let dropOpacity: CGFloat = 0.55

    private struct Band {
        let name: String
        let share: Float
    }

    // MARK: Build

    func build(size: CGSize) {
        self.size = size
        root.frame = CGRect(origin: .zero, size: size)
        root.masksToBounds = true
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        emitters.removeAll()
        bands.removeAll()
        lastDensities.removeAll()

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

        for layer in [Layer.rain, .embers] {
            let emitter = makeEmitter(for: layer, size: size)
            emitters[layer] = emitter
            root.addSublayer(emitter)
        }

        flash.frame = CGRect(origin: .zero, size: size)
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        flash.isHidden = true
        root.addSublayer(flash)
    }

    // MARK: Emitter construction

    private func makeEmitter(for layer: Layer, size: CGSize) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = CGRect(origin: .zero, size: size)
        emitter.renderMode = (layer == .embers) ? .additive : .unordered
        emitter.isHidden = true

        let built = makeCells(for: layer, size: size)
        // A closure rather than a key path: Swift has no key paths into tuples.
        emitter.emitterCells = built.map { $0.cell }
        bands[layer] = built.map { Band(name: $0.cell.name ?? "", share: $0.share) }

        switch layer {
        case .rain:
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height + 90)
            emitter.emitterSize = CGSize(width: size.width * 1.7, height: 1)
        case .embers:
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: -20)
            emitter.emitterSize = CGSize(width: size.width * 0.9, height: 1)
        case .thunder:
            break
        }

        return emitter
    }

    private func makeCells(for layer: Layer, size: CGSize) -> [(cell: CAEmitterCell, share: Float)] {
        let height = Float(size.height)

        switch layer {
        case .rain:
            return [
                (rainCell(name: "rain-far", texture: ParticleTextures.raindropFar,
                          velocity: 620, spread: 170, scale: 0.55, alpha: 0.44,
                          height: height, crossSpeed: 500), 0.55),
                (rainCell(name: "rain-mid", texture: ParticleTextures.raindropMid,
                          velocity: 1020, spread: 260, scale: 0.80, alpha: 0.72,
                          height: height, crossSpeed: 880), 0.30),
                (rainCell(name: "rain-near", texture: ParticleTextures.raindropNear,
                          velocity: 1560, spread: 380, scale: 1.05, alpha: 1.00,
                          height: height, crossSpeed: 1350), 0.15)
            ]

        case .embers:
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
            return [(cell, 1.0)]

        case .thunder:
            // Lightning is a full-screen flash, not a particle system.
            return []
        }
    }

    private func rainCell(name: String, texture: CGImage?, velocity: CGFloat, spread: CGFloat,
                          scale: CGFloat, alpha: CGFloat, height: Float, crossSpeed: Float) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.name = name
        cell.birthRate = 0
        cell.contents = texture
        cell.velocity = velocity
        cell.velocityRange = spread
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = 0.035
        cell.yAcceleration = -220
        cell.lifetime = height / crossSpeed + 0.7
        cell.scale = scale
        cell.scaleRange = scale * 0.32
        // Kept narrow deliberately. A wide alpha range pushes half the drops
        // down towards invisible, which reads as the rain washing out.
        cell.alphaRange = 0.14
        cell.color = NSColor(calibratedWhite: 1.0, alpha: alpha * Self.dropOpacity).cgColor
        return cell
    }

    // MARK: Drive

    /// A slow wander, from two sine waves whose periods do not divide into one
    /// another. Rain that always falls at the same angle looks printed on; a
    /// wind slider would be one more thing to fiddle with, so it drifts by
    /// itself instead.
    private func autoWind() -> Float {
        let t = CACurrentMediaTime()
        let a = sin(t * 0.037)
        let b = sin(t * 0.0113 + 1.7)
        return Float((a * 0.62 + b * 0.38) * 0.34)
    }

    func update(state: MixState) {
        guard size != .zero else { return }

        let areaScale = Float(max(size.width / 1920.0, 0.6))
        let drift = autoWind()

        for (layer, emitter) in emitters {
            guard let layerBands = bands[layer], !layerBands.isEmpty else { continue }

            let density = state.effectiveDensity(layer)
            let total = birthRate(for: layer, density: density) * areaScale
            let wasOff = (lastDensities[layer] ?? 0) <= 0.0001
            lastDensities[layer] = density

            if total <= 0 {
                for band in layerBands {
                    emitter.setValue(0, forKeyPath: "emitterCells.\(band.name).birthRate")
                }
                // Only on the transition to off, so an already-idle layer does
                // not queue a block every time it is visited.
                if !wasOff {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak emitter] in
                        guard let e = emitter, let first = layerBands.first else { return }
                        let current = e.value(forKeyPath: "emitterCells.\(first.name).birthRate") as? Float ?? 0
                        if current <= 0 { e.isHidden = true }
                    }
                }
                continue
            }

            if emitter.isHidden || wasOff {
                emitter.isHidden = false
                // Pre-roll so the scene arrives already full, rather than
                // filling in from the top edge over several seconds.
                emitter.beginTime = CACurrentMediaTime() - Double(preroll(for: layer))
            }

            for band in layerBands {
                emitter.setValue(total * band.share, forKeyPath: "emitterCells.\(band.name).birthRate")
            }

            if layer == .rain {
                for band in layerBands {
                    emitter.setValue(-Float.pi / 2 + drift * 0.30,
                                     forKeyPath: "emitterCells.\(band.name).emissionLongitude")
                    emitter.setValue(drift * 240,
                                     forKeyPath: "emitterCells.\(band.name).xAcceleration")
                }
            }
        }

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

    private func birthRate(for layer: Layer, density: Double) -> Float {
        guard density > 0.0001 else { return 0 }
        switch layer {
        case .rain:    return Float(density * density * 900 + density * 80)
        case .embers:  return Float(density * 85)
        case .thunder: return 0
        }
    }

    private func preroll(for layer: Layer) -> Float {
        switch layer {
        case .rain:    return 2
        case .embers:  return 4
        case .thunder: return 0
        }
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

    func resize(to newSize: CGSize) {
        guard newSize != size else { return }
        build(size: newSize)
    }
}
