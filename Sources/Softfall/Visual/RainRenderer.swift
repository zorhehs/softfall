import AppKit
import QuartzCore

/// Everything the rain renderer is told, in the same vocabulary as the lab the
/// numbers came from. Nothing here is persisted: the app derives it from the
/// mix state every frame.
struct RainParams: Equatable {
    /// 0...1. Drives how many drops there are, nothing else.
    var intensity: CGFloat = 0
    /// -0.6...0.6. Horizontal drift as a fraction of fall speed.
    var wind: CGFloat = 0
    /// Scales every band's alpha together, so the near/far relationship holds.
    var dropOpacity: CGFloat = 0.55
    /// 0 is white, 1 is a cold blue-grey.
    var blue: CGFloat = 0.70
    var speed: CGFloat = 1
    var length: CGFloat = 1
    var splashes: Bool = true
}

/// Rain, drawn by hand.
///
/// This replaced a `CAEmitterLayer`, for one reason above all others: an
/// emitter cell cannot be rotated to face its own velocity. Give emitter rain
/// a sideways push and the drops keep pointing straight down while sliding
/// across the screen, which reads as a broken sprite sheet rather than as
/// wind. Everything else here — tapered streaks, splashes, a frame rate we
/// choose — follows from owning the draw call.
///
/// The technique is the one the lab settled on: each depth band's drop is
/// drawn **once** into an offscreen sprite, and every frame that sprite is
/// blitted rotated. Rebuilding a gradient path 400 times a frame would be
/// hopeless; blitting a finished bitmap 400 times is ordinary work.
final class RainLayer: CALayer {

    // MARK: Shape of the curtain

    private struct Band {
        let share: CGFloat
        /// Points per second, at the reference height below.
        let speed: CGFloat
        /// Streak length in points, at the reference height below.
        let length: CGFloat
        let width: CGFloat
        /// Base alpha before `dropOpacity` scales the whole set.
        let alpha: CGFloat
        /// Far drops are too small for an impact to be legible, and splashing
        /// all of them costs a lot for something nobody can see.
        let splashes: Bool
    }

    private static let bands: [Band] = [
        Band(share: 0.55, speed: 520,  length: 34,  width: 1.0, alpha: 0.44, splashes: false),
        Band(share: 0.30, speed: 900,  length: 70,  width: 1.5, alpha: 0.72, splashes: true),
        Band(share: 0.15, speed: 1380, length: 118, width: 2.1, alpha: 1.00, splashes: true)
    ]

    /// The lab ran in an 800-point-tall stage, and its speeds and lengths were
    /// tuned by eye there. A 27-inch display is nearly three times that, so the
    /// numbers are scaled to keep the *time a drop takes to cross the screen*
    /// the same rather than the pixels per second.
    private static let referenceHeight: CGFloat = 800

    /// Above this the curtain gets more expensive without looking any wetter.
    private static let maxDrops = 1400
    private static let maxSplashes = 180

    // MARK: State

    private struct Drop {
        var band: Int
        var x: CGFloat
        var y: CGFloat
        /// Per-drop variation in speed and size. Without it the bands read as
        /// three distinct curtains rather than one continuous depth.
        var jitter: CGFloat
    }

    private struct SplashDrop {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
    }

    private struct Splash {
        var x: CGFloat
        var ring: CGFloat
        var life: CGFloat
        var strength: CGFloat
        var parts: [SplashDrop]
    }

    var params = RainParams() {
        didSet {
            if params.blue != oldValue.blue { sprites = []; litSprites = [] }
        }
    }

    private var drops: [Drop] = []
    private var splashes: [Splash] = []
    private var sprites: [CGImage] = []
    /// The same drops, pale, for the frames a lightning strike lights them.
    private var litSprites: [CGImage] = []
    private var litSince: CFTimeInterval = -1
    private var lit: CGFloat = 0
    private var heightScale: CGFloat = 1
    /// Reused between frames so retiring surplus drops allocates nothing.
    private var retired: [Int] = []

    // MARK: Lifecycle

    override init() {
        super.init()
        commonInit()
    }

    /// Core Animation makes a copy of every layer for the presentation tree,
    /// and it does so through this initialiser. A subclass that does not
    /// provide it will not compile once it has stored properties.
    override init(layer: Any) {
        super.init(layer: layer)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — Softfall builds its layers in code")
    }

    private func commonInit() {
        needsDisplayOnBoundsChange = false
        isOpaque = false
        // Nothing here is implicitly animatable, and the one property that
        // changes every frame is `contents`. Refusing actions outright keeps a
        // stray implicit animation from ever queueing behind a frame.
        actions = ["contents": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull()]
    }

    // MARK: Layout

    func configure(size: CGSize, scale: CGFloat) {
        let changed = bounds.size != size || contentsScale != scale
        frame = CGRect(origin: .zero, size: size)
        contentsScale = scale
        guard changed else { return }

        heightScale = max(size.height / Self.referenceHeight, 0.75)
        sprites = []
        drops.removeAll(keepingCapacity: true)
        splashes.removeAll(keepingCapacity: true)
    }

    /// Fill the screen in one go rather than letting it arrive from the top
    /// edge over several seconds. The emitter needed a negative `beginTime` for
    /// this; here it is just where the first drops are put.
    private func seed(count: Int) {
        drops.reserveCapacity(count)
        for _ in 0..<count {
            var drop = newDrop()
            drop.y = CGFloat.random(in: 0...bounds.height)
            drops.append(drop)
        }
    }

    private func newDrop() -> Drop {
        // Weighted by share, so the three bands stay in their intended
        // proportions however the count moves.
        let roll = CGFloat.random(in: 0...1)
        var band = Self.bands.count - 1
        var acc: CGFloat = 0
        for (index, b) in Self.bands.enumerated() {
            acc += b.share
            if roll <= acc { band = index; break }
        }
        return Drop(
            band: band,
            x: CGFloat.random(in: -bounds.width * 0.15...bounds.width * 1.15),
            y: bounds.height + length(of: band, jitter: 1),
            jitter: CGFloat.random(in: 0.75...1.25)
        )
    }

    private func targetCount() -> Int {
        guard params.intensity > 0.001 else { return 0 }
        let i = min(max(params.intensity, 0), 1)
        // Half the lab's curve. The lab was judged in a 1280x800 canvas inside
        // a web page; the same relative density across a whole desktop you are
        // trying to work under is simply too much weather.
        let base = 40 + i * i * 250 + i * 55
        // The lab's stage was 1280 points wide. A wider screen needs more drops
        // for the same apparent density; there is no point scaling with height
        // too, because the speed scaling above already fills a tall screen.
        let width = min(max(bounds.width / 1280, 0.6), 2.4)
        return min(Int(base * width), Self.maxDrops)
    }

    private func speed(of band: Int, jitter: CGFloat) -> CGFloat {
        Self.bands[band].speed * heightScale * jitter * params.speed
    }

    private func length(of band: Int, jitter: CGFloat) -> CGFloat {
        Self.bands[band].length * heightScale * jitter * params.length
    }

    var isIdle: Bool { drops.isEmpty && splashes.isEmpty }

    // MARK: Lightning

    /// Brightness of the flash on the rain over time, in seconds from the
    /// strike. Follows the bolt's own strokes, sampled a little coarser.
    private static let litCurve: [(time: CFTimeInterval, value: CGFloat)] = [
        (0, 0), (0.08, 1), (0.32, 0.6), (0.7, 0)
    ]

    /// A strike has just been drawn; catch it on the drops for the next few
    /// frames. Rain lit by lightning goes pale and a little brighter — it is
    /// what sells the bolt as being *in* the weather rather than over it.
    func lightUp() {
        litSince = CACurrentMediaTime()
    }

    private func sampleLit() -> CGFloat {
        guard litSince >= 0 else { return 0 }
        let t = CACurrentMediaTime() - litSince
        let curve = Self.litCurve
        guard t < curve[curve.count - 1].time else { litSince = -1; return 0 }
        for i in 1..<curve.count where t <= curve[i].time {
            let (t0, v0) = curve[i - 1], (t1, v1) = curve[i]
            return v0 + (v1 - v0) * CGFloat((t - t0) / (t1 - t0))
        }
        return 0
    }

    // MARK: Simulation

    /// One step. Called from the display link; never from the audio thread.
    func advance(dt: CGFloat) {
        guard bounds.height > 0 else { return }
        // A long stall — a wake from sleep, a stuck main thread — must not
        // teleport the whole curtain through the floor.
        let step = min(max(dt, 0), 0.05)

        let target = targetCount()
        if drops.isEmpty {
            // Either the first frame, or rain that was switched off and has
            // just come back. Both want a full screen immediately.
            if target > 0 { seed(count: target) }
        } else {
            while drops.count < target { drops.append(newDrop()) }
        }
        // Surplus drops are retired where they land rather than deleted where
        // they are. Turning the rain down — or off — then reads as the shower
        // passing, instead of half the screen blinking out.
        var surplus = max(0, drops.count - target)

        let drift = params.wind * 0.34
        let floor: CGFloat = 2

        for index in drops.indices {
            var drop = drops[index]
            let fall = speed(of: drop.band, jitter: drop.jitter)

            // Screen coordinates are y-up here, as everywhere else in Core
            // Animation, so falling is negative y.
            drop.y -= fall * step
            drop.x += fall * step * drift

            if drop.y <= floor {
                if params.splashes,
                   Self.bands[drop.band].splashes,
                   splashes.count < Self.maxSplashes,
                   CGFloat.random(in: 0...1) < 0.55 {
                    spawnSplash(at: drop.x, strength: drop.band == 2 ? 1.0 : 0.62)
                }
                if surplus > 0 {
                    surplus -= 1
                    retired.append(index)
                    drops[index] = drop
                    continue
                }
                drop = newDrop()
            }

            // Wrapping rather than respawning keeps a steady sideways wind from
            // slowly emptying one edge of the screen.
            if drop.x > bounds.width * 1.2 { drop.x -= bounds.width * 1.35 }
            if drop.x < -bounds.width * 0.2 { drop.x += bounds.width * 1.35 }

            drops[index] = drop
        }

        if !retired.isEmpty {
            for index in retired.reversed() { drops.remove(at: index) }
            retired.removeAll(keepingCapacity: true)
        }

        advanceSplashes(step)

        if target == 0 && isIdle {
            // Nothing left to draw. Drop the backing store so the last frame
            // cannot flash back when the rain returns, and let the controller
            // park the display link.
            isHidden = true
            contents = nil
            return
        }

        setNeedsDisplay()
    }

    private func spawnSplash(at x: CGFloat, strength: CGFloat) {
        var parts: [SplashDrop] = []
        let n = Int.random(in: 2...4)
        for _ in 0..<n {
            parts.append(SplashDrop(
                x: x + CGFloat.random(in: -2...2),
                y: 2,
                vx: CGFloat.random(in: -60...60) * strength,
                vy: CGFloat.random(in: 55...150) * strength
            ))
        }
        splashes.append(Splash(x: x, ring: 0, life: 1, strength: strength, parts: parts))
    }

    private func advanceSplashes(_ dt: CGFloat) {
        guard !splashes.isEmpty else { return }
        for index in splashes.indices.reversed() {
            splashes[index].life -= dt * 2.6
            splashes[index].ring += dt * (60 + 90 * splashes[index].strength)
            if splashes[index].life <= 0 {
                splashes.remove(at: index)
                continue
            }
            for p in splashes[index].parts.indices {
                splashes[index].parts[p].vy -= 620 * dt
                splashes[index].parts[p].x += splashes[index].parts[p].vx * dt
                splashes[index].parts[p].y += splashes[index].parts[p].vy * dt
            }
        }
    }

    // MARK: Drawing

    override func draw(in ctx: CGContext) {
        guard bounds.height > 0 else { return }
        if sprites.isEmpty { buildSprites() }
        guard sprites.count == Self.bands.count, litSprites.count == Self.bands.count else { return }
        lit = sampleLit()

        // Every drop shares one velocity direction, so the rotation is computed
        // once. Rotating the sprite's tail axis (0, 1) by this angle lands it
        // opposite the direction of travel, which is what makes wind-blown rain
        // point where it is actually going instead of sliding sideways.
        let drift = params.wind * 0.34
        let angle = atan2(drift, 1)

        ctx.setBlendMode(.normal)
        ctx.interpolationQuality = .medium

        for drop in drops {
            let band = Self.bands[drop.band]
            let len = length(of: drop.band, jitter: drop.jitter)
            let wide = band.width * 2.6 * drop.jitter
            let alpha = band.alpha * drop.jitter * params.dropOpacity

            ctx.saveGState()
            ctx.setAlpha(min(alpha, 1))
            ctx.translateBy(x: drop.x, y: drop.y)
            ctx.rotate(by: angle)
            // The head sits at the origin and the tail runs back up the sprite,
            // so a drop is positioned by where its point is — which is also
            // where it has to be when it hits the floor.
            let rect = CGRect(x: -wide * 0.5, y: 0, width: wide, height: len)
            ctx.draw(sprites[drop.band], in: rect)
            if lit > 0.02 {
                // Only while a strike is on screen — a second blit per drop
                // for well under a second.
                ctx.setAlpha(min(alpha + lit * 0.45, 1))
                ctx.draw(litSprites[drop.band], in: rect)
            }
            ctx.restoreGState()
        }

        drawSplashes(in: ctx)
    }

    private func drawSplashes(in ctx: CGContext) {
        guard !splashes.isEmpty else { return }
        let rgb = dropColour()

        for splash in splashes {
            let a = splash.life * splash.life * params.dropOpacity

            // A flattened ring, because you are looking along the surface
            // rather than down onto it.
            ctx.setStrokeColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: a * 0.42)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(
                x: splash.x - splash.ring,
                y: 2 - splash.ring * 0.26,
                width: splash.ring * 2,
                height: splash.ring * 0.52
            ))

            ctx.setFillColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: a * 0.85)
            let r = 1.0 + splash.strength * 0.7
            for p in splash.parts where p.y > 1 {
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    // MARK: Sprites

    /// Pure white reads as a scratch on the display; real rain picks up the
    /// colour of the sky behind it.
    private func dropColour() -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let blue = min(max(params.blue, 0), 1)
        // Widened from the lab's mapping, which only ever reached a pale tint.
        // At 0 this is still white, so the slider spans the whole useful range.
        return ((247 - blue * 190) / 255, (251 - blue * 110) / 255, 1.0)
    }

    private func buildSprites() {
        sprites = Self.bands.compactMap { makeSprite(for: $0, colour: dropColour()) }
        litSprites = Self.bands.compactMap { makeSprite(for: $0, colour: Self.litColour) }
    }

    /// Lightning-lit rain: pale, faintly warm, whatever blue it was before.
    private static let litColour: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.92, 0.93, 0.80)

    private func makeSprite(for band: Band, colour c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGImage? {
        // Sized generously against the largest destination rect a drop of this
        // band can ask for, so the blit is always a downscale.
        let pointWidth = band.width * 2.6 * 1.25
        let pointLength = band.length * heightScale * 1.25
        let px = max(2, Int((pointWidth * contentsScale * 2).rounded(.up)))
        let py = max(2, Int((pointLength * contentsScale).rounded(.up)))

        guard let ctx = CGContext(
            data: nil,
            width: px,
            height: py,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Work in a unit square with the tail at v = 0 and the head at v = 1,
        // so the shape is independent of how many pixels it was given.
        ctx.translateBy(x: 0, y: CGFloat(py))
        ctx.scaleBy(x: CGFloat(px), y: -CGFloat(py))

        // A thread at the tail swelling into a rounded head: what a falling
        // drop smeared across one frame actually looks like.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.5, y: 0))
        path.addLine(to: CGPoint(x: 0.86, y: 0.80))
        path.addQuadCurve(to: CGPoint(x: 0.14, y: 0.80), control: CGPoint(x: 0.5, y: 1.0))
        path.closeSubpath()

        let space = CGColorSpaceCreateDeviceRGB()
        let stops: [CGFloat] = [0, 0.45, 0.82, 0.95, 1.0]
        let alphas: [CGFloat] = [0, 0.22, 0.78, 1.0, 0.85]
        let colors = alphas.map { CGColor(colorSpace: space, components: [c.r, c.g, c.b, $0])! }
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops)
        else { return nil }

        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0.5, y: 0),
            end: CGPoint(x: 0.5, y: 1),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        return ctx.makeImage()
    }
}

/// Wraps the one display link the renderer runs on.
///
/// `CADisplayLink` only arrived on the Mac in macOS 14 — before that the
/// options were a `CVDisplayLink` on its own thread, which then has to hop back
/// to the main thread to touch a layer, or a timer that drifts against the
/// refresh rate. This is why Softfall now asks for Sonoma.
final class DisplayLinkDriver: NSObject {

    /// `#selector` needs an `@objc` method, and `@objc` needs an `NSObject`
    /// subclass — hence a small class of its own rather than a closure.
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var rate: RainFrameRate?

    /// Seconds since the previous frame.
    var onFrame: ((CGFloat) -> Void)?

    /// - Parameter view: the link is created from the view so that it follows
    ///   whichever display that view is on, including a mid-session drag from a
    ///   60 Hz panel to a ProMotion one.
    func start(in view: NSView, rate: RainFrameRate) {
        if link != nil {
            setFrameRate(rate)
            link?.isPaused = false
            return
        }
        let created = view.displayLink(target: self, selector: #selector(step(_:)))
        self.rate = nil
        apply(rate, to: created)
        created.add(to: .main, forMode: .common)
        last = 0
        link = created
    }

    func setFrameRate(_ rate: RainFrameRate) {
        guard let link else { return }
        apply(rate, to: link)
    }

    /// Unlike a CALayer — which has no such property on macOS, whatever the
    /// documentation implies — a display link can genuinely be asked for a
    /// rate, and the window server honours a range it can hit.
    private func apply(_ rate: RainFrameRate, to link: CADisplayLink) {
        guard rate != self.rate else { return }
        self.rate = rate

        if rate == .display {
            link.preferredFrameRateRange = CAFrameRateRange.default
            return
        }
        let fps = Float(rate.rawValue)
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: max(fps * 0.5, 15),
            maximum: fps,
            preferred: fps
        )
    }

    var isPaused: Bool {
        get { link?.isPaused ?? true }
        set {
            link?.isPaused = newValue
            if newValue { last = 0 }
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
        last = 0
        rate = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        // The first frame after a start or a resume has no predecessor, so bill
        // it one refresh interval rather than the length of the pause.
        let dt = last == 0 ? (link.targetTimestamp - now) : (now - last)
        last = now
        onFrame?(CGFloat(dt))
    }
}
