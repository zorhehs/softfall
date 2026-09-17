import Foundation

/// One element of the scene. Every layer is uniform: it may draw something,
/// it may make a sound, and a single "level" slider controls how much of it
/// there is. That uniformity is what keeps the interface small no matter how
/// many layers exist.
enum Layer: String, CaseIterable, Codable, Identifiable {
    case rain
    case snow
    case wind
    case thunder
    case fog
    case fireflies
    case embers
    case ocean
    case stream
    case drone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain:      return "Rain"
        case .snow:      return "Snow"
        case .wind:      return "Breeze"
        case .thunder:   return "Thunder"
        case .fog:       return "Fog"
        case .fireflies: return "Fireflies"
        case .embers:    return "Embers"
        case .ocean:     return "Ocean"
        case .stream:    return "Stream"
        case .drone:     return "Deep Hum"
        }
    }

    var subtitle: String {
        switch self {
        case .rain:      return "Falling streaks and a steady hiss"
        case .snow:      return "Drifting flakes, and the hush they bring"
        case .wind:      return "Slow gusts that never repeat"
        case .thunder:   return "Distant flashes, rumble following after"
        case .fog:       return "A soft haze that dims the edges"
        case .fireflies: return "Slow points of light, wandering"
        case .embers:    return "Rising sparks and a fire's crackle"
        case .ocean:     return "Swell and retreat"
        case .stream:    return "Water over stones"
        case .drone:     return "A low, level tone for deep focus"
        }
    }

    var symbol: String {
        switch self {
        case .rain:      return "cloud.rain.fill"
        case .snow:      return "cloud.snow.fill"
        case .wind:      return "wind"
        case .thunder:   return "cloud.bolt.fill"
        case .fog:       return "cloud.fog.fill"
        case .fireflies: return "sparkles"
        case .embers:    return "flame.fill"
        case .ocean:     return "water.waves"
        case .stream:    return "drop.fill"
        case .drone:     return "waveform"
        }
    }

    /// Whether this layer draws anything on screen.
    var hasVisual: Bool {
        switch self {
        case .ocean, .stream, .drone: return false
        default: return true
        }
    }

    /// Whether this layer makes any sound.
    var hasAudio: Bool {
        switch self {
        case .fog, .fireflies: return false
        default: return true
        }
    }

    var group: LayerGroup {
        switch self {
        case .rain, .snow, .wind, .thunder, .fog: return .sky
        case .fireflies, .embers:                 return .light
        case .ocean, .stream, .drone:             return .water
        }
    }
}

enum LayerGroup: String, CaseIterable, Identifiable {
    case sky
    case light
    case water

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sky:   return "Sky"
        case .light: return "Light"
        case .water: return "Water & Air"
        }
    }

    var layers: [Layer] {
        Layer.allCases.filter { $0.group == self }
    }
}

/// Per-layer user settings.
///
/// `visual` and `sound` are deliberately independent: you can have rain on
/// screen in silence, or rain in your ears with a still desktop. Muting the
/// sound never hides the picture and vice versa.
struct LayerSettings: Codable, Equatable {
    var visual: Bool
    var sound: Bool
    /// 0...1 — how much of this layer there is. Drives particle density and
    /// audio gain together, so one slider means one idea.
    var level: Double

    init(visual: Bool = false, sound: Bool = false, level: Double = 0.5) {
        self.visual = visual
        self.sound = sound
        self.level = level
    }

    /// Effective audio gain, 0 when muted.
    var audioGain: Double { sound ? level : 0 }
    /// Effective visual density, 0 when hidden.
    var visualDensity: Double { visual ? level : 0 }

    var isActive: Bool { (visual || sound) && level > 0.001 }
}
