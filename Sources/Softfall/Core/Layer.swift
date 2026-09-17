import Foundation

/// What the renderer and the synthesiser actually produce.
///
/// Deliberately not the same list as `Scene`. Thunder is lightning and rumble
/// *over* rain, so the Thunder scene drives two layers; keeping the two
/// vocabularies separate means the rain code is written once and reused,
/// instead of being duplicated inside a "thunder" case.
enum Layer: String, CaseIterable, Codable, Identifiable {
    case rain
    case thunder
    case embers

    var id: String { rawValue }

    /// Whether this layer draws anything on screen.
    var hasVisual: Bool { true }
    /// Whether this layer makes any sound.
    var hasAudio: Bool { true }
}

/// How often the rain renderer is asked to draw.
///
/// This setting existed once before and was removed, because `CALayer` has no
/// `preferredFrameRateRange` on macOS whatever the documentation implies. That
/// is no longer the obstacle: the renderer now owns a `CADisplayLink`, and a
/// display link genuinely can be asked for a rate.
enum RainFrameRate: Int, Codable, CaseIterable, Identifiable {
    case thirty = 30
    case sixty = 60
    /// Whatever the display can do, which on a ProMotion panel is 120.
    case display = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirty:  return "30 fps"
        case .sixty:   return "60 fps"
        case .display: return "Display"
        }
    }
}

/// What you choose. Three options, nothing else.
enum Scene: String, CaseIterable, Codable, Identifiable {
    case rain
    case thunder
    case campfire

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain:     return "Rain"
        case .thunder:  return "Thunder"
        case .campfire: return "Campfire"
        }
    }

    var blurb: String {
        switch self {
        case .rain:     return "Steady rain, and the sound of it."
        case .thunder:  return "Rain with lightning, and rumble following after."
        case .campfire: return "Embers lifting, wood cracking."
        }
    }

    var symbol: String {
        switch self {
        case .rain:     return "cloud.rain.fill"
        case .thunder:  return "cloud.bolt.rain.fill"
        case .campfire: return "flame.fill"
        }
    }

    /// The layers this scene switches on.
    var layers: [Layer] {
        switch self {
        case .rain:     return [.rain]
        case .thunder:  return [.rain, .thunder]
        case .campfire: return [.embers]
        }
    }

    /// Some layers should sit under the one you actually chose rather than
    /// matching it. Rain under a thunderstorm is the weather, not the event.
    func weight(for layer: Layer) -> Double {
        switch (self, layer) {
        case (.thunder, .thunder): return 0.55
        default:                   return 1.0
        }
    }
}

/// How much of the chosen scene there is, and whether you want to see it,
/// hear it, or both.
///
/// Picture and sound stay independent: rain on screen in silence, or rain in
/// your ears with a still desktop, are both things people want.
struct SceneSettings: Codable, Equatable {
    var picture: Bool
    var sound: Bool
    /// 0...1 — drives particle density and audio character together.
    var level: Double

    init(picture: Bool = true, sound: Bool = true, level: Double = 0.5) {
        self.picture = picture
        self.sound = sound
        self.level = level
    }

    var isActive: Bool { (picture || sound) && level > 0.001 }
}
