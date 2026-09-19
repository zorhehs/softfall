import Foundation

/// One strike of lightning, decided once and then performed twice: drawn by
/// the renderer and played by the thunder voice.
///
/// The picture and the sound used to each get a single number — distance —
/// and improvise from it separately. Neither could match the other, because
/// neither knew what the other had done. Now the director rolls the whole
/// event up front: what kind of strike it is, how long the leader takes to
/// creep down, and exactly when each return stroke re-lights the channel. The
/// bolt flickers on those strokes, the sky blooms on those strokes, and for a
/// strike close enough to crack, the crack comes once per stroke at the same
/// intervals. What you hear is the flicker you just saw.
struct LightningStrike {

    enum Kind {
        /// Cloud to ground: a stepped leader, then return strokes down one
        /// channel. Forks light with the first stroke and die with it.
        case bolt
        /// Cloud to cloud, spreading sideways across the top of the sky. Slow,
        /// many-fingered, gentle — and no crack, only a long roll.
        case crawler
        /// Behind cloud. No channel to see; the sky pulses, and the thunder
        /// is the dull far kind.
        case sheet
    }

    /// One re-lighting of the channel.
    struct ReturnStroke {
        /// Seconds after the leader begins.
        var time: Double
        /// Brightness relative to the first stroke, 0...1.
        var strength: Double
    }

    var kind: Kind
    /// 0 is overhead, 1 is far off.
    var distance: Double
    /// Seconds the leader takes to reach the ground before the first stroke.
    var leaderDuration: Double
    var strokes: [ReturnStroke]

    /// The gust that runs ahead of the strike. A storm front pushes air in
    /// front of it, so the rain leans, and the bed of sound swells, a moment
    /// before the sky lights. `gustLead` is how long before; zero means no
    /// gust — a strike behind cloud is too far away to feel.
    var gustLead: Double = 0
    /// 0...1, by nearness.
    var gustStrength: Double = 0
    /// -1 or +1: which way the rain leans.
    var gustDirection: Double = 1

    var nearness: Double { 1 - distance }

    /// Only the nearest strikes crack; the rest are all body.
    var cracks: Bool { kind == .bolt && distance < 0.45 }

    /// From leader start to the end of the afterglow.
    var duration: Double {
        (strokes.last?.time ?? 0) + 0.9
    }

    /// Beyond this a strike is behind cloud: a bloom, no visible bolt.
    static let boltVisibleWithin: Double = 0.85

    static func roll(distance: Double) -> LightningStrike {
        var rng = SystemRandomNumberGenerator()
        return roll(distance: distance, using: &rng)
    }

    static func roll<G: RandomNumberGenerator>(distance: Double, using rng: inout G) -> LightningStrike {
        let d = min(max(distance, 0), 1)
        let near = 1 - d

        let kind: Kind
        if d >= boltVisibleWithin {
            kind = .sheet
        } else if d > 0.3 && Double.random(in: 0..<1, using: &rng) < 0.28 {
            // Crawlers are a mid-distance sight: overhead you get the bolt,
            // far off you get the sheet.
            kind = .crawler
        } else {
            kind = .bolt
        }

        var strokes: [ReturnStroke] = []
        let leader: Double

        switch kind {
        case .bolt:
            // The leader is dim and quick; a near strike has more strokes,
            // each a little weaker. They are spaced a tenth of a second or so
            // apart — further than the real thing, which is tens of
            // milliseconds, because a stroke has to last a few frames to be
            // seen at all, and strokes closer together than that merge into
            // one.
            leader = Double.random(in: 0.04...0.12, using: &rng)
            let count = 1 + Int(Double.random(in: 0..<(1.4 + near * 2.6), using: &rng))
            var t = leader
            var strength = 1.0
            for index in 0..<min(count, 4) {
                strokes.append(ReturnStroke(time: t, strength: strength))
                t += Double.random(in: 0.09...0.18, using: &rng)
                strength = index == 0
                    ? Double.random(in: 0.55...0.9, using: &rng)
                    : strength * Double.random(in: 0.7...0.95, using: &rng)
            }

        case .crawler:
            // Slow enough to watch it travel. Its strokes are soft and
            // unhurried; it never snaps.
            leader = Double.random(in: 0.28...0.55, using: &rng)
            let count = Int.random(in: 2...3, using: &rng)
            var t = leader
            for _ in 0..<count {
                strokes.append(ReturnStroke(time: t, strength: Double.random(in: 0.5...0.8, using: &rng)))
                t += Double.random(in: 0.09...0.22, using: &rng)
            }

        case .sheet:
            leader = 0
            let count = Int.random(in: 2...4, using: &rng)
            var t = 0.0
            for _ in 0..<count {
                strokes.append(ReturnStroke(time: t, strength: Double.random(in: 0.4...1.0, using: &rng)))
                t += Double.random(in: 0.06...0.18, using: &rng)
            }
        }

        var strike = LightningStrike(kind: kind, distance: d, leaderDuration: leader, strokes: strokes)
        if kind != .sheet {
            // Nearer is shorter and sharper: the front is almost on you.
            strike.gustLead = Double.random(in: 0.6...1.3, using: &rng) - near * 0.3
            strike.gustStrength = 0.35 + near * 0.65
            strike.gustDirection = Bool.random(using: &rng) ? 1 : -1
        }
        return strike
    }
}
