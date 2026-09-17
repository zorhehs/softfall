import AppKit
import QuartzCore

/// Builds and drives the Core Animation particle layers.
///
/// Core Animation's emitter runs on the GPU, so an always-on overlay costs a
/// fraction of what a per-frame software canvas would. That matters a lot when
/// the intended use is "leave it running all day on a laptop".
final class SceneLayers {

    let root = CALayer()
    private let flash = CALayer()
    private var emitters: [Layer: CAEmitterLayer] = [:]
    private var size: CGSize = .zero
    private var lastDensities: [Layer: Double] = [:]

    // MARK: Build

    func build(size: CGSize) {
        self.size = size
        root.frame = CGRect(origin: .zero, size: size)
        root.masksToBounds = true
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        emitters.removeAll()
        lastDensities.removeAll()

        // Fog sits furthest back, lightning in front of everything.
        for layer in [Layer.fog, .rain, .snow, .wind, .embers, .fireflies] {
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
        emitter.renderMode = (layer == .fireflies || layer == .embers) ? .additive : .unordered
        emitter.emitterCells = [makeCell(for: layer, size: size)]
        emitter.isHidden = true

        switch layer {
        case .rain, .snow:
            // Emit from a line above the top edge so particles are already at
            // full speed by the time they enter the visible area.
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height + 60)
            emitter.emitterSize = CGSize(width: size.width * 1.6, height: 1)
        case .wind, .fog:
            emitter.emitterShape = .rectangle
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height / 2)
            emitter.emitterSize = CGSize(width: size.width * 1.4, height: size.height)
        case .embers:
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: -20)
            emitter.emitterSize = CGSize(width: size.width * 0.9, height: 1)
        case .fireflies:
            emitter.emitterShape = .rectangle
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height * 0.45)
            emitter.emitterSize = CGSize(width: size.width, height: size.height * 0.8)
        default:
            break
        }

        return emitter
    }

    private func makeCell(for layer: Layer, size: CGSize) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.name = layer.rawValue
        cell.birthRate = 0
        let crossing = Float(size.height)

        switch layer {
        case .rain:
            cell.contents = ParticleTextures.raindrop
            cell.velocity = 1250
            cell.velocityRange = 420
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = 0.045
            cell.yAcceleration = -220
            cell.lifetime = crossing / 900 + 0.8
            cell.scale = 0.9
            cell.scaleRange = 0.55
            cell.alphaRange = 0.35
            cell.color = NSColor(calibratedWhite: 1.0, alpha: 0.42).cgColor

        case .snow:
            cell.contents = ParticleTextures.snowflake
            cell.velocity = 58
            cell.velocityRange = 34
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = 0.5
            cell.yAcceleration = -6
            cell.xAcceleration = 4
            cell.lifetime = crossing / 40 + 4
            cell.scale = 0.42
            cell.scaleRange = 0.32
            cell.alphaRange = 0.4
            cell.spin = 0.25
            cell.spinRange = 0.9
            cell.color = NSColor(calibratedWhite: 1.0, alpha: 0.72).cgColor

        case .wind:
            // Faint motes that make a breeze visible without anything falling.
            cell.contents = ParticleTextures.mote
            cell.velocity = 210
            cell.velocityRange = 130
            cell.emissionLongitude = 0
            cell.emissionRange = 0.32
            cell.lifetime = 9
            cell.lifetimeRange = 4
            cell.scale = 0.5
            cell.scaleRange = 0.4
            cell.alphaSpeed = -0.12
            cell.alphaRange = 0.25
            cell.color = NSColor(calibratedWhite: 1.0, alpha: 0.30).cgColor

        case .fog:
            cell.contents = ParticleTextures.haze()
            cell.velocity = 16
            cell.velocityRange = 12
            cell.emissionLongitude = 0
            cell.emissionRange = 0.6
            cell.lifetime = 34
            cell.lifetimeRange = 12
            cell.scale = 2.4
            cell.scaleRange = 1.6
            cell.scaleSpeed = 0.06
            cell.alphaSpeed = -0.028
            cell.color = NSColor(calibratedWhite: 1.0, alpha: 0.30).cgColor

        case .embers:
            cell.contents = ParticleTextures.ember
            cell.velocity = 95
            cell.velocityRange = 55
            cell.emissionLongitude = .pi / 2      // upward
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
            cell.color = NSColor(calibratedRed: 1.0, green: 0.60, blue: 0.24, alpha: 0.85).cgColor

        case .fireflies:
            cell.contents = ParticleTextures.firefly
            cell.velocity = 17
            cell.velocityRange = 13
            cell.emissionRange = .pi * 2
            cell.lifetime = 13
            cell.lifetimeRange = 6
            cell.scale = 0.30
            cell.scaleRange = 0.18
            // Fade in and back out so each one reads as a slow pulse rather
            // than a dot that blinks into existence.
            cell.alphaSpeed = -0.14
            cell.alphaRange = 0.3
            cell.color = NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.55, alpha: 0.9).cgColor

        default:
            break
        }

        return cell
    }

    // MARK: Drive

    func update(state: MixState, windLevel: Double) {
        guard size != .zero else { return }

        // Wider displays need proportionally more particles to feel the same.
        let areaScale = Float(max(size.width / 1920.0, 0.6))

        for (layer, emitter) in emitters {
            let density = state.effectiveDensity(layer)
            let rate = birthRate(for: layer, density: density) * areaScale

            let wasOff = (lastDensities[layer] ?? 0) <= 0.0001
            lastDensities[layer] = density

            if rate <= 0 {
                emitter.setValue(0, forKeyPath: "emitterCells.\(layer.rawValue).birthRate")
                // Only on the transition to off. Scheduling this every time an
                // already-idle layer is visited would queue a block per layer
                // per update, which during a slider drag is hundreds a second.
                if !wasOff {
                    // Leave the layer up for a moment so particles already in
                    // flight finish falling instead of vanishing mid-air.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak emitter] in
                        guard let e = emitter else { return }
                        let current = e.value(forKeyPath: "emitterCells.\(layer.rawValue).birthRate") as? Float ?? 0
                        if current <= 0 { e.isHidden = true }
                    }
                }
                continue
            }

            if emitter.isHidden || wasOff {
                emitter.isHidden = false
                // Pre-roll so the scene arrives already full rather than
                // filling in from the top edge over several seconds.
                emitter.beginTime = CACurrentMediaTime() - Double(preroll(for: layer))
            }

            emitter.setValue(rate, forKeyPath: "emitterCells.\(layer.rawValue).birthRate")

            // Wind pushes rain, snow and motes sideways; the same value also
            // drives the audio, so what you see and what you hear agree.
            let drift = Float(windLevel)
            switch layer {
            case .rain:
                emitter.setValue(-Float.pi / 2 + drift * 0.30,
                                 forKeyPath: "emitterCells.rain.emissionLongitude")
                emitter.setValue(drift * 240, forKeyPath: "emitterCells.rain.xAcceleration")
            case .snow:
                emitter.setValue(drift * 34 + 4, forKeyPath: "emitterCells.snow.xAcceleration")
            case .wind:
                emitter.setValue(60 + drift * 320, forKeyPath: "emitterCells.wind.velocity")
            case .fog:
                emitter.setValue(6 + drift * 40, forKeyPath: "emitterCells.fog.velocity")
            default:
                break
            }
        }

        let target = Float(state.isPlaying ? state.opacity : 0)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        root.opacity = target
        CATransaction.commit()
    }

    private func birthRate(for layer: Layer, density: Double) -> Float {
        guard density > 0.0001 else { return 0 }
        switch layer {
        case .rain:      return Float(density * density * 620 + density * 40)
        case .snow:      return Float(density * 140)
        case .wind:      return Float(density * 34)
        case .fog:       return Float(density * 2.6)
        case .embers:    return Float(density * 85)
        case .fireflies: return Float(density * 7)
        default:         return 0
        }
    }

    private func preroll(for layer: Layer) -> Float {
        switch layer {
        case .rain:      return 1.5
        case .snow:      return 8
        case .fog:       return 20
        case .wind:      return 6
        case .embers:    return 4
        case .fireflies: return 8
        default:         return 0
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
