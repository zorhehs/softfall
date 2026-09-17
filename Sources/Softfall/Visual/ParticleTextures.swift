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

    static var ember: CGImage? { softDot(diameter: 16, core: 0.1, peakAlpha: 1.0) }
}
