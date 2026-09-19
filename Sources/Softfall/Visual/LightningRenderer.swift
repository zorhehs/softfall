import AppKit
import QuartzCore

/// A drawn lightning bolt.
///
/// What was here before was a white rectangle fading in and out. That reads as
/// a camera flash, not as lightning: the thing your eye actually recognises is
/// the *shape* — a jagged line with forks, gone almost before you have seen it.
///
/// The bolt is drawn once per strike rather than every frame. Its geometry does
/// not change while it is on screen; only its brightness does, and that is a
/// keyframe animation on `opacity`. So this needs no display link, and works
/// even with the rain switched off.
///
/// The layer sizes itself to the bolt's bounding box rather than to the screen.
/// A full-screen backing store at 2x on a large display is tens of megabytes to
/// hold on to between strikes, for a shape that occupies a fraction of it.
final class LightningLayer: CALayer {

    /// Struck yellow rather than the blue-white of the real thing. That is a
    /// deliberate look, not an accident of the physics.
    private static let core = CGColor(red: 1.00, green: 0.97, blue: 0.80, alpha: 1)
    private static let inner = CGColor(red: 1.00, green: 0.88, blue: 0.42, alpha: 1)
    private static let outer = CGColor(red: 1.00, green: 0.76, blue: 0.20, alpha: 1)

    /// Beyond this the strike is behind cloud: a bloom, no visible bolt.
    ///
    /// This was 0.62, chosen without checking it against the distance the
    /// director actually picks — which is `1 - level ... 1`. The two ranges
    /// barely overlapped: at the default level a bolt appeared about once
    /// every ninety seconds, and below a level of 0.38 no bolt could ever be
    /// drawn at all, because every strike was classified as behind cloud.
    /// Now most strikes draw one, and distance decides how strong it is
    /// rather than whether it exists.
    private static let boltVisibleWithin: Double = 0.88

    private var path: CGPath?
    private var strength: CGFloat = 1
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
        actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(),
                   "hidden": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull()]
    }

    // MARK: Striking

    /// - Parameters:
    ///   - distance: 0 is overhead, 1 is far off.
    ///   - opacityScale: the overlay's own opacity setting.
    ///   - size: the screen, in points. The bolt is placed within it and then
    ///     the layer shrinks to fit what it drew.
    func strike(distance: Double, opacityScale: Double, in size: CGSize, scale: CGFloat) {
        let d = min(max(distance, 0), 1)
        guard d < Self.boltVisibleWithin, size.width > 0, size.height > 0 else { return }

        // Near strikes are thicker, brighter and reach further down the screen.
        let nearness = CGFloat(1 - d / Self.boltVisibleWithin)
        strength = 0.45 + nearness * 0.55

        let built = Self.makeBolt(in: size, nearness: nearness)
        let padding = 26 * strength
        var box = built.boundingBoxOfPath.insetBy(dx: -padding, dy: -padding)
        box = box.intersection(CGRect(origin: .zero, size: size).insetBy(dx: -padding, dy: -padding))
        guard !box.isNull, box.width > 1, box.height > 1 else { return }

        // Move the path into the layer's own coordinates so the backing store
        // only has to cover the bolt.
        var shift = CGAffineTransform(translationX: -box.origin.x, y: -box.origin.y)
        path = built.copy(using: &shift)

        contentsScale = scale
        frame = box
        isHidden = false
        setNeedsDisplay()
        displayIfNeeded()

        strikeID += 1
        let token = strikeID

        removeAllAnimations()
        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        let peak = Float(min(max(opacityScale, 0), 1))
        // Two strokes and a die-back. Even, regular pulsing reads as a lamp.
        flicker.values = [0, peak, peak * 0.18, peak * 0.92, peak * 0.25, peak * 0.5, 0]
        flicker.keyTimes = [0, 0.02, 0.09, 0.14, 0.26, 0.36, 1.0]
        flicker.duration = 0.42 + Double(1 - nearness) * 0.35
        flicker.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flicker.isRemovedOnCompletion = true
        add(flicker, forKey: "strike")

        // Give the backing store back afterwards. The token guards against a
        // later strike being cleaned up by an earlier strike's timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + flicker.duration + 0.1) { [weak self] in
            guard let self, self.strikeID == token else { return }
            self.isHidden = true
            self.contents = nil
            self.path = nil
        }
    }

    // MARK: Shape

    /// Midpoint displacement: repeatedly split every segment and push the new
    /// middle sideways by a shrinking amount. It is the standard way to get a
    /// line that looks like it was torn rather than drawn, and it is what makes
    /// the bolt read as lightning rather than as a zigzag.
    private static func makeBolt(in size: CGSize, nearness: CGFloat) -> CGPath {
        let startX = CGFloat.random(in: size.width * 0.12...size.width * 0.88)
        // Coordinates are y-up: the bolt starts above the top edge and comes
        // down. Near strikes reach further; distant ones peter out high up.
        let start = CGPoint(x: startX, y: size.height + 12)
        let drop = size.height * (0.30 + nearness * 0.38)
        let end = CGPoint(
            x: startX + CGFloat.random(in: -size.width * 0.16...size.width * 0.16),
            y: size.height - drop
        )

        var points = displace([start, end], jitter: size.width * 0.045, steps: 6)

        let path = CGMutablePath()
        path.addLines(between: points)

        // One or two forks, branching off the upper half and travelling less
        // far. A bolt with no forks looks like a crack in the screen.
        let forks = Int.random(in: 1...2)
        for _ in 0..<forks {
            guard points.count > 6 else { break }
            let index = Int.random(in: 2...(points.count - 3))
            let from = points[index]
            let to = CGPoint(
                x: from.x + CGFloat.random(in: -size.width * 0.13...size.width * 0.13),
                y: from.y - drop * CGFloat.random(in: 0.18...0.42)
            )
            let branch = displace([from, to], jitter: size.width * 0.022, steps: 4)
            path.addLines(between: branch)
        }

        return path
    }

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

    // MARK: Drawing

    override func draw(in ctx: CGContext) {
        guard let path else { return }

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // Additive, so where the forks cross the glow piles up and brightens,
        // the way a real one does.
        ctx.setBlendMode(.plusLighter)

        // Widest and dimmest first, finishing with a thin hot core.
        let passes: [(width: CGFloat, alpha: CGFloat, colour: CGColor)] = [
            (22 * strength, 0.05, Self.outer),
            (12 * strength, 0.10, Self.outer),
            (6.5 * strength, 0.22, Self.inner),
            (3.0 * strength, 0.55, Self.inner),
            (1.4 * strength, 0.95, Self.core)
        ]

        for pass in passes {
            ctx.setStrokeColor(pass.colour.copy(alpha: pass.alpha) ?? pass.colour)
            ctx.setLineWidth(max(pass.width, 0.6))
            ctx.addPath(path)
            ctx.strokePath()
        }
    }
}
