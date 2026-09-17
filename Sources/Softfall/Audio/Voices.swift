import Foundation

/// A stereo sample pair.
typealias Frame = (l: Double, r: Double)

// MARK: - Rain

/// Rain is three things stacked: a soft broadband bed, a low roar that carries
/// the weight, and individual droplets.
///
/// The bed is built from **pink** noise, not white. White noise has equal
/// energy per hertz, which piles most of its power into the top octaves and is
/// what makes naive "rain" synthesis sound like a hairdryer. Rain has a
/// downward spectral tilt, so pink is the right starting point and the rest of
/// the chain only takes away from there.
///
/// The whole thing is then deliberately rolled off with two cascaded lowpass
/// stages. The target is rain heard through a window from a warm room, not
/// rain hitting a microphone — the difference between the two is almost
/// entirely how much energy survives above 4 kHz.
struct RainVoice {
    private var rngL: Random
    private var rngR: Random
    private var pinkL = PinkNoise(), pinkR = PinkNoise()
    private var brownL = BrownNoise(), brownR = BrownNoise()

    // Two lowpass stages per channel gives a ~24 dB/octave slope. One stage
    // leaves an audible hiss shelf; two sounds soft.
    private var lp1L = Biquad(), lp1R = Biquad()
    private var lp2L = Biquad(), lp2R = Biquad()
    private var hpL = Biquad(), hpR = Biquad()
    private var roarL = Biquad(), roarR = Biquad()

    private var gust: RandomWalk
    private var drift: RandomWalk
    private var droplets: [Droplet]
    private var dropletRng: Random
    private var nextDroplet: Double = 0
    private var dropIndex = 0
    private var retuneCounter = 0
    private var roarGain: Double = 0.4
    private let sampleRate: Double

    private struct Droplet {
        var env: Double = 0
        var decay: Double = 0.999
        var pan: Double = 0.5
        var filter = Biquad()
        var excite: Double = 0
    }

    init(sampleRate: Double, seed: UInt64) {
        self.sampleRate = sampleRate
        rngL = Random(seed: seed &+ 11)
        rngR = Random(seed: seed &+ 12)
        dropletRng = Random(seed: seed &+ 13)
        gust = RandomWalk(seed: seed &+ 14, lo: 0.86, hi: 1.12, minSeconds: 4, maxSeconds: 12, sampleRate: sampleRate)
        // A slow wander on the cutoff. Static never changes; rain always does,
        // and this is most of what the ear uses to tell them apart.
        drift = RandomWalk(seed: seed &+ 15, lo: 0.88, hi: 1.14, minSeconds: 6, maxSeconds: 17, sampleRate: sampleRate)
        droplets = Array(repeating: Droplet(), count: 10)
    }

    private mutating func retune(_ intensity: Double, _ driftAmount: Double) {
        // Light rain is distant and muffled; heavy rain moves closer and opens
        // up. Even at full intensity this stays well below the old 9 kHz.
        let cutoff = lerp(1750, 4100, intensity) * driftAmount
        lp1L.set(.lowpass, freq: cutoff, q: 0.62, sampleRate: sampleRate)
        lp1R.set(.lowpass, freq: cutoff * 0.94, q: 0.62, sampleRate: sampleRate)
        lp2L.set(.lowpass, freq: cutoff * 1.22, q: 0.54, sampleRate: sampleRate)
        lp2R.set(.lowpass, freq: cutoff * 1.15, q: 0.54, sampleRate: sampleRate)

        // Clear the very bottom so the bed does not fight the roar.
        let hp = lerp(165, 100, intensity)
        hpL.set(.highpass, freq: hp, q: 0.55, sampleRate: sampleRate)
        hpR.set(.highpass, freq: hp * 1.08, q: 0.55, sampleRate: sampleRate)

        let roarCut = lerp(195, 440, intensity)
        roarL.set(.lowpass, freq: roarCut, q: 0.68, sampleRate: sampleRate)
        roarR.set(.lowpass, freq: roarCut * 0.92, q: 0.68, sampleRate: sampleRate)

        // Present even in drizzle. Without low weight the bed is just hiss.
        roarGain = lerp(0.34, 0.92, intensity)
    }

    mutating func render(intensity: Double) -> Frame {
        let driftAmount = drift.step()

        retuneCounter += 1
        if retuneCounter >= 64 {
            retuneCounter = 0
            retune(intensity, driftAmount)
        }

        let g = gust.step()

        let nl = pinkL.process(rngL.bipolar())
        let nr = pinkR.process(rngR.bipolar())

        var l = lp2L.process(lp1L.process(hpL.process(nl))) * 1.55 * g
        var r = lp2R.process(lp1R.process(hpR.process(nr))) * 1.55 * g

        l += roarL.process(brownL.process(rngL.bipolar())) * roarGain
        r += roarR.process(brownR.process(rngR.bipolar())) * roarGain

        // Far more of them, pitched lower, and much quieter. Sparse high ticks
        // read as an irritant; a dense low scatter reads as texture.
        let ratePerSecond = lerp(28.0, 78.0, intensity)
        nextDroplet -= 1.0
        if nextDroplet <= 0 {
            nextDroplet = (dropletRng.range(0.35, 1.9) / ratePerSecond) * sampleRate
            dropIndex = (dropIndex + 1) % droplets.count
            var d = droplets[dropIndex]
            let top = lerp(1900.0, 3100.0, intensity)
            d.filter.set(.bandpass,
                         freq: dropletRng.range(520, top),
                         q: dropletRng.range(1.8, 4.5),
                         sampleRate: sampleRate)
            d.decay = exp(-1.0 / (dropletRng.range(0.010, 0.048) * sampleRate))
            d.env = dropletRng.range(0.2, 1.0)
            d.pan = dropletRng.unit()
            d.excite = 1.0
            droplets[dropIndex] = d
        }

        for i in droplets.indices where droplets[i].env > 0.0005 {
            var d = droplets[i]
            let input = d.excite + dropletRng.bipolar() * 0.45
            d.excite = 0
            let s = d.filter.process(input) * d.env * 0.17
            d.env *= d.decay
            droplets[i] = d
            l += s * (1.0 - d.pan)
            r += s * d.pan
        }

        return (l * 0.46, r * 0.46)
    }
}

// MARK: - Thunder

/// Fired on demand rather than free-running, so the flash on screen can lead
/// the sound by the right amount. `distance` is 0 (overhead) to 1 (far off)
/// and controls every other parameter at once.
struct ThunderVoice {
    private var rngL: Random, rngR: Random
    private var brownL = BrownNoise(), brownR = BrownNoise()
    private var lpL = Biquad(), lpR = Biquad()
    private var subL = Biquad(), subR = Biquad()
    private var rumble: RandomWalk
    private var env: Double = 0
    private var attackRamp: Double = 0
    private var attackRate: Double = 0
    private var decay: Double = 0
    private var amplitude: Double = 0
    private var subAmount: Double = 0
    private let sampleRate: Double

    init(sampleRate: Double, seed: UInt64) {
        self.sampleRate = sampleRate
        rngL = Random(seed: seed &+ 31)
        rngR = Random(seed: seed &+ 32)
        rumble = RandomWalk(seed: seed &+ 33, lo: 0.35, hi: 1.0, minSeconds: 0.18, maxSeconds: 0.85, sampleRate: sampleRate)
        subL.set(.lowpass, freq: 48, q: 0.8, sampleRate: sampleRate)
        subR.set(.lowpass, freq: 46, q: 0.8, sampleRate: sampleRate)
    }

    var isIdle: Bool { env < 0.0002 && attackRamp <= 0 }

    mutating func strike(distance: Double) {
        let d = min(max(distance, 0), 1)
        let cutoff = lerp(460, 85, d)
        lpL.set(.lowpass, freq: cutoff, q: 0.7, sampleRate: sampleRate)
        lpR.set(.lowpass, freq: cutoff * 0.94, q: 0.7, sampleRate: sampleRate)
        attackRate = 1.0 / (lerp(0.018, 0.30, d) * sampleRate)
        decay = exp(-1.0 / (lerp(2.4, 8.5, d) * sampleRate))
        amplitude = lerp(1.0, 0.42, d)
        subAmount = lerp(0.9, 0.05, d)
        attackRamp = 0.0001
        env = 0
    }

    mutating func render() -> Frame {
        if attackRamp > 0 {
            attackRamp += attackRate
            env = min(attackRamp, 1.0)
            if attackRamp >= 1.0 { attackRamp = 0 }
        } else {
            env *= decay
            if env < 0.0002 { env = 0; return (0, 0) }
        }

        // The wobble is what separates thunder from a whoosh.
        let wob = rumble.step()
        let e = env * amplitude * wob

        let nl = brownL.process(rngL.bipolar())
        let nr = brownR.process(rngR.bipolar())

        var l = lpL.process(nl) * e
        var r = lpR.process(nr) * e
        l += subL.process(nl) * e * subAmount * 1.4
        r += subR.process(nr) * e * subAmount * 1.4

        return (l * 0.85, r * 0.85)
    }
}

// MARK: - Fire

struct FireVoice {
    private var rngL: Random, rngR: Random
    private var brownL = BrownNoise(), brownR = BrownNoise()
    private var bedL = Biquad(), bedR = Biquad()
    private var crackles: [Crackle]
    private var crackleRng: Random
    private var nextCrackle: Double = 0
    private var index = 0
    private var breath: RandomWalk
    private let sampleRate: Double

    private struct Crackle {
        var env: Double = 0
        var decay: Double = 0.99
        var pan: Double = 0.5
        var filter = Biquad()
        var excite: Double = 0
    }

    init(sampleRate: Double, seed: UInt64) {
        self.sampleRate = sampleRate
        rngL = Random(seed: seed &+ 61)
        rngR = Random(seed: seed &+ 62)
        crackleRng = Random(seed: seed &+ 63)
        crackles = Array(repeating: Crackle(), count: 8)
        breath = RandomWalk(seed: seed &+ 64, lo: 0.55, hi: 1.0, minSeconds: 1.5, maxSeconds: 5.5, sampleRate: sampleRate)
        bedL.set(.lowpass, freq: 640, q: 0.7, sampleRate: sampleRate)
        bedR.set(.lowpass, freq: 600, q: 0.7, sampleRate: sampleRate)
    }

    mutating func render(intensity: Double) -> Frame {
        let b = breath.step()
        var l = bedL.process(brownL.process(rngL.bipolar())) * b * 0.9
        var r = bedR.process(brownR.process(rngR.bipolar())) * b * 0.9

        let rate = lerp(4.0, 26.0, intensity)
        nextCrackle -= 1.0
        if nextCrackle <= 0 {
            nextCrackle = (crackleRng.range(0.25, 2.1) / rate) * sampleRate
            index = (index + 1) % crackles.count
            var c = crackles[index]
            c.filter.set(.bandpass, freq: crackleRng.range(1500, 6200), q: crackleRng.range(2.0, 6.0), sampleRate: sampleRate)
            c.decay = exp(-1.0 / (crackleRng.range(0.003, 0.028) * sampleRate))
            c.env = crackleRng.range(0.3, 1.0)
            c.pan = crackleRng.unit()
            c.excite = 1.0
            crackles[index] = c
        }

        for i in crackles.indices where crackles[i].env > 0.0005 {
            var c = crackles[i]
            let input = c.excite + crackleRng.bipolar() * 0.5
            c.excite = 0
            let s = c.filter.process(input) * c.env * 0.55
            c.env *= c.decay
            crackles[i] = c
            l += s * (1.0 - c.pan)
            r += s * c.pan
        }

        return (l * 0.55, r * 0.55)
    }
}
