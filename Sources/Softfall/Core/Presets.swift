import Foundation

/// A named starting point. Most people will pick one of these once and never
/// open the mixer at all — which is the point.
struct Preset: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let blurb: String
    let layers: [Layer: LayerSettings]

    static func == (lhs: Preset, rhs: Preset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private static func mix(_ pairs: [(Layer, Bool, Bool, Double)]) -> [Layer: LayerSettings] {
        var d: [Layer: LayerSettings] = [:]
        for layer in Layer.allCases {
            d[layer] = LayerSettings(visual: false, sound: false, level: 0.5)
        }
        for (layer, visual, sound, level) in pairs {
            d[layer] = LayerSettings(visual: visual, sound: sound, level: level)
        }
        return d
    }

    static let all: [Preset] = [
        Preset(
            id: "quiet-rain",
            title: "Quiet Rain",
            symbol: "cloud.drizzle.fill",
            blurb: "Light rain and a low haze. The default for a reason.",
            layers: mix([
                (.rain, true, true, 0.38),
                (.fog,  true, false, 0.22)
            ])
        ),
        Preset(
            id: "downpour",
            title: "Downpour",
            symbol: "cloud.heavyrain.fill",
            blurb: "Heavy rain, wind, and thunder rolling through.",
            layers: mix([
                (.rain,    true, true, 0.88),
                (.wind,    true, true, 0.45),
                (.thunder, true, true, 0.5),
                (.fog,     true, false, 0.35)
            ])
        ),
        Preset(
            id: "snowfall",
            title: "Snowfall",
            symbol: "snowflake",
            blurb: "Slow flakes and the particular quiet that comes with them.",
            layers: mix([
                (.snow, true, true, 0.5),
                (.wind, false, true, 0.18),
                (.fog,  true, false, 0.4)
            ])
        ),
        Preset(
            id: "campfire",
            title: "Campfire",
            symbol: "flame.fill",
            blurb: "Embers lifting, wood cracking, fireflies in the dark.",
            layers: mix([
                (.embers,    true, true, 0.55),
                (.fireflies, true, false, 0.3),
                (.wind,      false, true, 0.15)
            ])
        ),
        Preset(
            id: "shoreline",
            title: "Shoreline",
            symbol: "water.waves",
            blurb: "Swell, retreat, and salt air.",
            layers: mix([
                (.ocean, false, true, 0.6),
                (.wind,  true, true, 0.35),
                (.fog,   true, false, 0.3)
            ])
        ),
        Preset(
            id: "forest-stream",
            title: "Forest Stream",
            symbol: "leaf.fill",
            blurb: "Water over stones, with something glowing in the trees.",
            layers: mix([
                (.stream,    false, true, 0.5),
                (.fireflies, true, false, 0.35),
                (.wind,      true, true, 0.2)
            ])
        ),
        Preset(
            id: "deep-focus",
            title: "Deep Focus",
            symbol: "brain.head.profile",
            blurb: "A level hum under fine rain. Nothing moves fast.",
            layers: mix([
                (.drone, false, true, 0.35),
                (.rain,  false, true, 0.45),
                (.fog,   true, false, 0.18)
            ])
        ),
        Preset(
            id: "night-window",
            title: "Night Window",
            symbol: "moon.stars.fill",
            blurb: "Rain on glass, far-off thunder, lights in the dark.",
            layers: mix([
                (.rain,      true, true, 0.5),
                (.thunder,   true, true, 0.22),
                (.fireflies, true, false, 0.2),
                (.fog,       true, false, 0.3)
            ])
        )
    ]
}
