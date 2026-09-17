import Foundation

// MARK: - Deterministic, allocation-free noise

/// xorshift128+ — fast, good quality, and safe to call from the audio thread
/// because it never allocates and never touches the Swift runtime.
struct Random {
    private var s0: UInt64
    private var s1: UInt64

    init(seed: UInt64) {
        // splitmix64 to spread a small seed across the full state
        var z = seed &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        s0 = z ^ (z >> 31)
        z = seed &+ 0x7F4A7C15_9E3779B9
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        s1 = z ^ (z >> 31)
        if s0 == 0 && s1 == 0 { s0 = 0x2545F4914F6CDD1D }
    }

    mutating func next() -> UInt64 {
        var x = s0
        let y = s1
        s0 = y
        x ^= x << 23
        s1 = x ^ y ^ (x >> 17) ^ (y >> 26)
        return s1 &+ y
    }

    /// Uniform in [0, 1)
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Uniform in [-1, 1)
    mutating func bipolar() -> Double {
        unit() * 2.0 - 1.0
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }
}

// MARK: - Coloured noise

/// Paul Kellet's economy pink-noise filter. Roughly -3 dB/octave, which is
/// the spectrum most natural "hiss" sources (rain, surf) sit closest to.
struct PinkNoise {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0

    mutating func process(_ white: Double) -> Double {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return out * 0.11 // normalise back to roughly unity RMS
    }
}

/// Leaky integrator — -6 dB/octave. The low rumble under thunder and fire.
struct BrownNoise {
    private var last = 0.0

    mutating func process(_ white: Double) -> Double {
        last = (last + 0.02 * white) / 1.02
        return last * 3.5
    }
}

// MARK: - Biquad (RBJ cookbook, transposed direct form II)

struct Biquad {
    enum Kind { case lowpass, highpass, bandpass, peaking }

    private var a1 = 0.0, a2 = 0.0, b0 = 1.0, b1 = 0.0, b2 = 0.0
    private var z1 = 0.0, z2 = 0.0

    /// - Parameters:
    ///   - freq: centre/corner frequency in Hz. Clamped to a safe range so a
    ///     runaway modulator can never produce NaN on the audio thread.
    ///   - q: resonance. Clamped to >= 0.05.
    mutating func set(_ kind: Kind, freq: Double, q: Double, sampleRate: Double, gainDB: Double = 0) {
        let nyquist = sampleRate * 0.5
        let f = min(max(freq, 10.0), nyquist * 0.98)
        let qq = max(q, 0.05)
        let w0 = 2.0 * Double.pi * f / sampleRate
        let cosw = cos(w0)
        let sinw = sin(w0)
        let alpha = sinw / (2.0 * qq)

        var nb0 = 0.0, nb1 = 0.0, nb2 = 0.0, na0 = 1.0, na1 = 0.0, na2 = 0.0

        switch kind {
        case .lowpass:
            nb0 = (1.0 - cosw) * 0.5
            nb1 = 1.0 - cosw
            nb2 = (1.0 - cosw) * 0.5
            na0 = 1.0 + alpha
            na1 = -2.0 * cosw
            na2 = 1.0 - alpha
        case .highpass:
            nb0 = (1.0 + cosw) * 0.5
            nb1 = -(1.0 + cosw)
            nb2 = (1.0 + cosw) * 0.5
            na0 = 1.0 + alpha
            na1 = -2.0 * cosw
            na2 = 1.0 - alpha
        case .bandpass:
            nb0 = alpha
            nb1 = 0.0
            nb2 = -alpha
            na0 = 1.0 + alpha
            na1 = -2.0 * cosw
            na2 = 1.0 - alpha
        case .peaking:
            let A = pow(10.0, gainDB / 40.0)
            nb0 = 1.0 + alpha * A
            nb1 = -2.0 * cosw
            nb2 = 1.0 - alpha * A
            na0 = 1.0 + alpha / A
            na1 = -2.0 * cosw
            na2 = 1.0 - alpha / A
        }

        b0 = nb0 / na0
        b1 = nb1 / na0
        b2 = nb2 / na0
        a1 = na1 / na0
        a2 = na2 / na0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        // Guard against denormal/NaN creep during hours of continuous playback.
        if !y.isFinite {
            z1 = 0; z2 = 0
            return 0
        }
        return y
    }

    mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

// MARK: - Parameter smoothing

/// One-pole smoother. Every user-facing parameter passes through one of these
/// so dragging a slider can never produce a click or a zipper artefact.
struct Smoothed {
    private(set) var value: Double
    private let coeff: Double

    init(_ initial: Double, ms: Double = 60, sampleRate: Double) {
        value = initial
        coeff = exp(-1.0 / (max(ms, 1.0) * 0.001 * sampleRate))
    }

    mutating func step(towards target: Double) -> Double {
        value = target + (value - target) * coeff
        if abs(value - target) < 1e-9 { value = target }
        return value
    }

    mutating func snap(to target: Double) {
        value = target
    }
}

/// A slow, smooth random walk. Drives wind gusts and ocean swell — anything
/// that should feel organic rather than periodic.
struct RandomWalk {
    private var current: Double
    private var target: Double
    private var rate: Double
    private var rng: Random
    private let lo: Double
    private let hi: Double
    private let minSeconds: Double
    private let maxSeconds: Double
    private let sampleRate: Double

    init(seed: UInt64, lo: Double, hi: Double, minSeconds: Double, maxSeconds: Double, sampleRate: Double) {
        self.rng = Random(seed: seed)
        self.lo = lo
        self.hi = hi
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
        self.sampleRate = sampleRate
        self.current = rng.range(lo, hi)
        self.target = rng.range(lo, hi)
        self.rate = 1.0 / (rng.range(minSeconds, maxSeconds) * sampleRate)
    }

    mutating func step() -> Double {
        current += (target - current) * rate
        if abs(target - current) < (hi - lo) * 0.01 {
            target = rng.range(lo, hi)
            rate = 1.0 / (rng.range(minSeconds, maxSeconds) * sampleRate)
        }
        return current
    }
}

// MARK: - Helpers

@inline(__always)
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * min(max(t, 0.0), 1.0)
}

@inline(__always)
func softClip(_ x: Double) -> Double {
    // tanh-ish curve without the transcendental cost. Keeps the master bus
    // musical if several layers peak together instead of hard-clipping.
    if x <= -1.5 { return -1.0 }
    if x >= 1.5 { return 1.0 }
    return x - (x * x * x) / 6.75
}
