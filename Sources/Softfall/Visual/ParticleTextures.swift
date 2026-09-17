import CoreGraphics
import AppKit

/// Every particle texture is drawn at launch rather than shipped as a file.
/// The app therefore contains no image assets, stays a few hundred kilobytes,
/// and renders correctly at any backing scale factor.
enum ParticleTextures {

    private static var cache: [String: CGImage] = [:]

    private static func makeContext(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// A soft circular falloff. `core` is the fraction of the radius that stays
    /// at full opacity before the fade begins — small values read as a glow,
    /// large values as a solid dot.
    static func softDot(diameter: Int, core: CGFloat = 0.15, peakAlpha: CGFloat = 1.0) -> CGImage? {
        let key = "dot-\(diameter)-\(core)-\(peakAlpha)"
        if let cached = cache[key] { return cached }
        guard let ctx = makeContext(diameter, diameter) else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(colorSpace: space, components: [1, 1, 1, peakAlpha])!,
            CGColor(colorSpace: space, components: [1, 1, 1, peakAlpha * 0.5])!,
            CGColor(colorSpace: space, components: [1, 1, 1, 0])!
        ]
        guard let gradient = CGGradient(
            colorsSpace: space,
            colors: colors as CFArray,
            locations: [0, core + 0.25, 1.0]
        ) else { return nil }

        let r = CGFloat(diameter) * 0.5
        let centre = CGPoint(x: r, y: r)
        ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: r, options: [])

        let image = ctx.makeImage()
        if let image { cache[key] = image }
        return image
    }

    /// A vertical streak, made by drawing the same soft falloff into a stretched
    /// coordinate system. Used for rain.
    static func streak(width: Int, height: Int, peakAlpha: CGFloat = 0.9) -> CGImage? {
        let key = "streak-\(width)-\(height)-\(peakAlpha)"
        if let cached = cache[key] { return cached }
        guard let ctx = makeContext(width, height) else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        // A touch of blue keeps rain from reading as a scratch on the display.
        // A near-white core with only a hint of blue. The previous version was
        // blue enough that it disappeared into any cool wallpaper.
        let colors = [
            CGColor(colorSpace: space, components: [1.0, 1.0, 1.0, peakAlpha])!,
            CGColor(colorSpace: space, components: [0.93, 0.96, 1.0, peakAlpha * 0.62])!,
            CGColor(colorSpace: space, components: [0.84, 0.90, 1.0, 0])!
        ]
        guard let gradient = CGGradient(
            colorsSpace: space,
            colors: colors as CFArray,
            locations: [0, 0.38, 1.0]
        ) else { return nil }

        ctx.saveGState()
        ctx.translateBy(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.5)
        ctx.scaleBy(x: 1.0, y: CGFloat(height) / CGFloat(width))
        let r = CGFloat(width) * 0.5
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: r, options: [])
        ctx.restoreGState()

        let image = ctx.makeImage()
        if let image { cache[key] = image }
        return image
    }

    /// A large, very faint blob. Many of these overlapping become fog.
    static func haze(diameter: Int = 256) -> CGImage? {
        softDot(diameter: diameter, core: 0.0, peakAlpha: 0.16)
    }

    /// Three streak lengths, one per depth band. A single texture scaled up
    /// and down cannot do this: scaling changes width and length together, so
    /// a "near" drop ends up fat rather than long. Rain reads as rain mainly
    /// because of how elongated it is, so each band gets its own aspect.
    static var raindropFar: CGImage? { streak(width: 5, height: 40, peakAlpha: 0.92) }
    static var raindropMid: CGImage? { streak(width: 7, height: 78, peakAlpha: 0.95) }
    static var raindropNear: CGImage? { streak(width: 9, height: 126, peakAlpha: 1.0) }

    static var snowflake: CGImage? { softDot(diameter: 18, core: 0.18, peakAlpha: 0.95) }
    static var firefly: CGImage? { softDot(diameter: 28, core: 0.06, peakAlpha: 1.0) }
    static var ember: CGImage? { softDot(diameter: 16, core: 0.1, peakAlpha: 1.0) }
    static var mote: CGImage? { softDot(diameter: 10, core: 0.1, peakAlpha: 0.55) }
}
