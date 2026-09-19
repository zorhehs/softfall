import AppKit
import QuartzCore

/// A drawn lightning bolt.
///
/// What was here first was a white rectangle fading in and out, which reads as
/// a camera flash. Then a jagged line with forks, drawn once and flickered by
/// an opacity animation — which reads as lightning, but lightning that
/// switches on. The real thing has an order of events your eye knows even if
/// you have never named them: a dim leader creeps down first, the channel
/// snaps bright when it connects, the forks light with that first stroke and
/// are gone, and then the main channel alone re-lights a few more times.
///
/// The bolt is three shape layers over one path — a wide warm glow, a thin
/// blue-white core, and the forks — so the leader is a `strokeEnd` animation
/// on the channel, the strokes are opacity keyframes taken straight from the
/// `LightningStrike`, and the forks get a short keyframe of their own. None of
/// it needs a display link, and it works with the rain switched off.
///
/// The layer sizes itself to the bolt's bounding box rather than to the screen:
/// a full-screen backing store at 2x on a large display is tens of megabytes
/// to hold between strikes, for a shape that occupies a fraction of it.
final class LightningLayer: CALayer {

    /// A blue-white core — the colour of the real thing — wrapped in a yellow
    /// glow that is not. The pairing was chosen by eye against a preview: all
    /// yellow read as a cartoon, all blue vanished into the rain.
    private static let core = CGColor(red: 0.86, green: 0.94, blue: 1.00, alpha: 1)
    private static let inner = CGColor(red: 0.46, green: 0.72, blue: 1.00, alpha: 1)
    private static let glow = CGColor(red: 1.00, green: 0.88, blue: 0.45, alpha: 1)
    private static let halo = CGColor(red: 1.00, green: 0.78, blue: 0.24, alpha: 1)

    private let glowLayer = CAShapeLayer()
    private let coreLayer = CAShapeLayer()
    private let forkLayer = CAShapeLayer()

    private var strikeID = 0

    override init() {
        super.init()
        commonInit()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — Softfall builds its layers in code")
    }

    private func commonInit() {
        isHidden = true
        opacity = 0
        let still: [String: CAAction] = [
            "position": NSNull(), "bounds": NSNull(), "hidden": NSNull(),
            "path": NSNull(), "strokeEnd": NSNull(), "opacity": NSNull(),
            "lineWidth": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull()
        ]
        actions = still

        for shape in [glowLayer, coreLayer, forkLayer] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.actions = still
            shape.shadowOffset = .zero
            addSublayer(shape)
        }

        // The glow is a wide, faint warm stroke with a wider, fainter shadow
        // of itself — two passes for the price of one layer.
        glowLayer.strokeColor = Self.glow.copy(alpha: 0.22)
        glowLayer.shadowColor = Self.halo
        glowLayer.shadowOpacity = 0.55

        coreLayer.strokeColor = Self.core
        coreLayer.shadowColor = Self.inner
        coreLayer.shadowOpacity = 1.0

        forkLayer.strokeColor = Self.inner.copy(alpha: 0.9)
        forkLayer.shadowColor = Self.glow
        forkLayer.shadowOpacity = 0.7
        forkLayer.opacity = 0
    }

    // MARK: Striking

    /// - Parameters:
    ///   - strike: what to draw, and when each stroke lights.
    ///   - opacityScale: the overlay's own opacity setting.
    ///   - size: the screen, in points. The bolt is placed within it and then
    ///     the layer shrinks to fit what it drew.
    /// - Returns: where the bolt left the top of the screen, in points, so the
    ///   sheet flash can bloom from the same place. `nil` when there is no bolt
    ///   to see.
    @discardableResult
    func strike(_ strike: LightningStrike, opacityScale: Double, in size: CGSize, scale: CGFloat) -> CGPoint? {
        guard strike.kind != .sheet, size.width > 0, size.height > 0,
              let first = strike.strokes.first else { return nil }

        let nearness = CGFloat(1 - strike.distance / LightningStrike.boltVisibleWithin)
        // Near strikes are thicker, brighter and reach further down the screen.
        let strength = 0.45 + nearness * 0.55

        let built: (channel: CGPath, forks: CGPath, origin: CGPoint)
        switch strike.kind {
        case .bolt:    built = Self.makeBolt(in: size, nearness: nearness)
        case .crawler: built = Self.makeCrawler(in: size, nearness: nearness)
        case .sheet:   return nil
        }

        let padding = 36 * strength
        var box = built.channel.boundingBoxOfPath
            .union(built.forks.boundingBoxOfPath)
            .insetBy(dx: -padding, dy: -padding)
        box = box.intersection(CGRect(origin: .zero, size: size).insetBy(dx: -padding, dy: -padding))
        guard !box.isNull, box.width > 1, box.height > 1 else { return nil }

        // Move the paths into the layer's own coordinates so the backing store
        // only has to cover the bolt.
        var shift = CGAffineTransform(translationX: -box.origin.x, y: -box.origin.y)
        let channel = built.channel.copy(using: &shift)
        let forks = built.forks.copy(using: &shift)

        contentsScale = scale
        frame = box
        for shape in [glowLayer, coreLayer, forkLayer] {
            shape.frame = bounds
            shape.contentsScale = scale
            shape.removeAllAnimations()
        }

        glowLayer.path = channel
        glowLayer.lineWidth = 14 * strength
        glowLayer.shadowRadius = 14 * strength

        coreLayer.path = channel
        coreLayer.lineWidth = max(1.7 * strength, 0.8)
        coreLayer.shadowRadius = 4.5 * strength

        forkLayer.path = forks
        forkLayer.lineWidth = max(1.1 * strength, 0.6)
        forkLayer.shadowRadius = 5 * strength

        isHidden = false
        removeAllAnimations()

        strikeID += 1
        let token = strikeID

        let peak = Float(min(max(opacityScale, 0), 1))
        let leader = strike.leaderDuration

        // The leader: the channel draws itself top to bottom, dim.
        if leader > 0 {
            for shape in [glowLayer, coreLayer] {
                let grow = CABasicAnimation(keyPath: "strokeEnd")
                grow.fromValue = 0
                grow.toValue = 1
                grow.duration = leader
                grow.timingFunction = CAMediaTimingFunction(name: .easeIn)
                grow.fillMode = .backwards
                shape.add(grow, forKey: "leader")
            }
        }

        // The strokes: a keyframe per return stroke, from the strike itself.
        // The channel sits at leader brightness until the first one, holds a
        // dimmer afterglow between them, then fades rather than cuts.
        let leaderGlow = peak * Float(0.10 + nearness * 0.10)
        let between = peak * Float(0.06 + nearness * 0.08)
        var keyframes: [(time: Double, value: Float)] = [(0, leaderGlow * 0.6), (max(leader - 0.004, 0.001), leaderGlow)]
        for stroke in strike.strokes {
            let v = peak * Float(stroke.strength)
            keyframes.append((stroke.time, v))
            keyframes.append((stroke.time + 0.018, v * 0.72))
            keyframes.append((stroke.time + 0.045, between))
        }
        let last = strike.strokes.last?.time ?? leader
        keyframes.append((last + 0.20, between * 0.7))
        keyframes.append((last + 0.55, between * 0.25))
        keyframes.append((strike.duration, 0))
        add(Self.flicker(keyframes, duration: strike.duration), forKey: "strike")

        // The forks: lit by the first stroke, and gone with it. Crawlers are
        // the exception — their fingers are the whole show and linger.
        let forkHold = strike.kind == .crawler ? 0.30 : 0.10
        let forkKeys: [(time: Double, value: Float)] = [
            (0, 0), (max(first.time - 0.003, 0), 0), (first.time, 1),
            (first.time + forkHold * 0.4, 0.55), (first.time + forkHold, 0), (strike.duration, 0)
        ]
        forkLayer.add(Self.flicker(forkKeys, duration: strike.duration), forKey: "forks")

        // Give the backing stores back afterwards. The token guards against a
        // later strike being cleaned up by an earlier strike's timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + strike.duration + 0.1) { [weak self] in
            guard let self, self.strikeID == token else { return }
            self.isHidden = true
            for shape in [self.glowLayer, self.coreLayer, self.forkLayer] {
                shape.removeAllAnimations()
                shape.path = nil
            }
        }
        return built.origin
    }

    private static func flicker(_ keyframes: [(time: Double, value: Float)], duration: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.duration = duration
        animation.values = keyframes.map { $0.value }
        animation.keyTimes = keyframes.map { NSNumber(value: min(max($0.time / duration, 0), 1)) }
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = true
        return animation
    }

    // MARK: Shape

    /// Cloud to ground. Coordinates are y-up: the bolt starts above the top
    /// edge and comes down. Near strikes reach further; distant ones peter out
    /// high up.
    private static func makeBolt(in size: CGSize, nearness: CGFloat) -> (channel: CGPath, forks: CGPath, origin: CGPoint) {
        let startX = CGFloat.random(in: size.width * 0.12...size.width * 0.88)
        let start = CGPoint(x: startX, y: size.height + 12)
        let drop = size.height * (0.30 + nearness * 0.38)
        let end = CGPoint(
            x: startX + CGFloat.random(in: -size.width * 0.16...size.width * 0.16),
            y: size.height - drop
        )

        let points = displace([start, end], jitter: size.width * 0.045, steps: 6)
        let channel = CGMutablePath()
        channel.addLines(between: points)

        // Two or three forks, branching off the upper half and travelling less
        // far. A bolt with no forks looks like a crack in the screen.
        let forks = CGMutablePath()
        for _ in 0..<Int.random(in: 2...3) {
            guard points.count > 6 else { break }
            let index = Int.random(in: 2...(points.count - 3))
            let from = points[index]
            let to = CGPoint(
                x: from.x + CGFloat.random(in: -size.width * 0.13...size.width * 0.13),
                y: from.y - drop * CGFloat.random(in: 0.18...0.42)
            )
            forks.addLines(between: displace([from, to], jitter: size.width * 0.022, steps: 4))
        }

        return (channel, forks, CGPoint(x: startX, y: size.height))
    }

    /// Cloud to cloud: enters from one side near the top and crawls across,
    /// sagging a little, with many short fingers reaching down and up. The
    /// path runs in the direction of travel so the leader animation walks it.
    private static func makeCrawler(in size: CGSize, nearness: CGFloat) -> (channel: CGPath, forks: CGPath, origin: CGPoint) {
        let leftToRight = Bool.random()
        let span = size.width * CGFloat.random(in: 0.45...0.85)
        let startX = leftToRight
            ? CGFloat.random(in: 0...(size.width - span))
            : CGFloat.random(in: span...size.width)
        let endX = leftToRight ? startX + span : startX - span
        let top = size.height * CGFloat.random(in: 0.80...0.94)
        let start = CGPoint(x: startX, y: top)
        let end = CGPoint(x: endX, y: top - size.height * CGFloat.random(in: 0.02...0.10))

        let points = displace([start, end], jitter: size.height * 0.03, steps: 6)
        let channel = CGMutablePath()
        channel.addLines(between: points)

        let forks = CGMutablePath()
        for _ in 0..<Int.random(in: 5...8) {
            guard points.count > 6 else { break }
            let index = Int.random(in: 2...(points.count - 3))
            let from = points[index]
            let down: CGFloat = Bool.random() ? -1 : 0.5
            let to = CGPoint(
                x: from.x + CGFloat.random(in: -size.width * 0.06...size.width * 0.06),
                y: from.y + down * size.height * CGFloat.random(in: 0.05...0.14)
            )
            forks.addLines(between: displace([from, to], jitter: size.width * 0.012, steps: 4))
        }

        return (channel, forks, CGPoint(x: (startX + endX) * 0.5, y: size.height))
    }

    /// Midpoint displacement: repeatedly split every segment and push the new
    /// middle sideways by a shrinking amount. It is the standard way to get a
    /// line that looks like it was torn rather than drawn, and it is what makes
    /// the bolt read as lightning rather than as a zigzag.
    private static func displace(_ input: [CGPoint], jitter: CGFloat, steps: Int) -> [CGPoint] {
        var points = input
        var offset = jitter
        for _ in 0..<steps {
            var next: [CGPoint] = [points[0]]
            next.reserveCapacity(points.count * 2)
            for i in 0..<(points.count - 1) {
                let a = points[i], b = points[i + 1]
                let dx = b.x - a.x, dy = b.y - a.y
                let length = max(sqrt(dx * dx + dy * dy), 0.0001)
                // Unit normal, so the kink is across the run of the bolt
                // rather than along it.
                let nx = -dy / length, ny = dx / length
                let push = CGFloat.random(in: -offset...offset)
                next.append(CGPoint(x: (a.x + b.x) * 0.5 + nx * push,
                                    y: (a.y + b.y) * 0.5 + ny * push))
                next.append(b)
            }
            points = next
            offset *= 0.55
        }
        return points
    }
}
