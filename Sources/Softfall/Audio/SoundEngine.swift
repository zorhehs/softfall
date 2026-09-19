import Foundation
import AVFoundation

/// Holds every voice and the parameters the audio thread reads.
///
/// Parameters are plain `Double`s written from the main thread and read from
/// the render thread without a lock. Aligned 64-bit loads and stores are
/// atomic on every platform this app runs on, and each value additionally
/// passes through a one-pole smoother, so the worst case for a race is that a
/// gain arrives one buffer late — which is inaudible. Taking a lock here would
/// be the genuinely dangerous choice.
private final class Synth {
    let sampleRate: Double
    /// Snapshotted at init. `Layer.allCases` is computed and allocates a fresh
    /// array on every access, which must never happen on the audio thread.
    let kinds: [Layer] = Layer.allCases
    let count = Layer.allCases.count

    var rain: RainVoice
    var thunderA: ThunderVoice
    var thunderB: ThunderVoice
    var fire: FireVoice

    var gains: [Double]
    var levels: [Double]
    var smoothers: [Smoothed]
    var masterSmoother: Smoothed
    var master: Double = 1.0

    /// 0 is rain through a closed window, 1 is through an open one. Read on
    /// the audio thread like every other parameter here.
    var rainTone: Double = 0.35

    var thunderRequest = false
    var thunderCue = ThunderCue()
    private var useThunderB = false

    var gustRequest = false
    var gustStrength = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let seed = UInt64(Date().timeIntervalSince1970 * 1000) | 1
        rain = RainVoice(sampleRate: sampleRate, seed: seed)
        thunderA = ThunderVoice(sampleRate: sampleRate, seed: seed &+ 3000)
        thunderB = ThunderVoice(sampleRate: sampleRate, seed: seed &+ 3500)
        fire = FireVoice(sampleRate: sampleRate, seed: seed &+ 6000)

        gains = Array(repeating: 0, count: count)
        levels = Array(repeating: 0.5, count: count)
        smoothers = (0..<count).map { _ in Smoothed(0, ms: 120, sampleRate: sampleRate) }
        masterSmoother = Smoothed(1.0, ms: 80, sampleRate: sampleRate)
    }

    /// Round-robin so a second strike during a long roll layers over the first
    /// instead of cutting it off.
    func consumeThunderRequest() {
        guard thunderRequest else { return }
        thunderRequest = false
        let cue = thunderCue
        if useThunderB { thunderB.strike(cue) } else { thunderA.strike(cue) }
        useThunderB.toggle()
    }

    func consumeGustRequest() {
        guard gustRequest else { return }
        gustRequest = false
        rain.blow(strength: gustStrength)
    }
}

/// The audio side of the app.
///
/// Inherits NSObject because it observes an AVAudioEngine notification by
/// selector, and `@objc` members are only permitted on Objective-C classes.
final class SoundEngine: NSObject {

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var synth: Synth?
    private var isRunning = false
    private let indexOf: [Layer: Int]

    override init() {
        var map: [Layer: Int] = [:]
        for (i, layer) in Layer.allCases.enumerated() { map[layer] = i }
        indexOf = map

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        build()
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            NSLog("Softfall: audio engine failed to start — \(error.localizedDescription)")
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    private func build() {
        if let existing = sourceNode {
            engine.detach(existing)
            sourceNode = nil
        }

        let hardware = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hardware.sampleRate > 0 ? hardware.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            NSLog("Softfall: could not create a stereo output format")
            return
        }

        let synth = Synth(sampleRate: sampleRate)
        self.synth = synth

        let node = AVAudioSourceNode(format: format) { [synth] _, _, frameCount, audioBufferList in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 1 else { return noErr }

            let left = ablPointer[0].mData?.assumingMemoryBound(to: Float.self)
            let right = ablPointer.count > 1
                ? ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
                : left

            synth.consumeThunderRequest()
            synth.consumeGustRequest()

            let masterTarget = synth.master

            for frame in 0..<Int(frameCount) {
                var l = 0.0
                var r = 0.0

                // Each layer is skipped entirely once its smoothed gain has
                // settled at zero, so an idle scene costs almost nothing.
                for index in 0..<synth.count {
                    let g = synth.smoothers[index].step(towards: synth.gains[index])
                    if g < 0.00002 { continue }
                    let level = synth.levels[index]

                    let f: Frame
                    switch synth.kinds[index] {
                    case .rain:
                        f = synth.rain.render(intensity: level, tone: synth.rainTone)
                    case .thunder:
                        let a = synth.thunderA.render()
                        let b = synth.thunderB.render()
                        f = (a.l + b.l, a.r + b.r)
                    case .embers:
                        f = synth.fire.render(intensity: level)
                    }

                    l += f.l * g
                    r += f.r * g
                }

                let m = synth.masterSmoother.step(towards: masterTarget)
                left?[frame] = Float(softClip(l * m))
                right?[frame] = Float(softClip(r * m))
            }

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    @objc private func handleConfigurationChange() {
        // Fires when headphones are plugged in, an output device disappears,
        // or the sample rate changes underneath us. Rebuilding is the only
        // reliable response, and it must happen off the notification thread.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.engine.stop()
            self.isRunning = false
            self.start()
        }
    }

    // MARK: Parameters

    func apply(_ state: MixState) {
        guard let synth else { return }
        for layer in Layer.allCases {
            guard let index = indexOf[layer] else { continue }
            synth.gains[index] = state.effectiveGain(layer)
            synth.levels[index] = state.level(layer)
        }
        synth.rainTone = state.rainTone
        synth.master = state.isPlaying ? 1.0 : 0.0
    }

    /// Called by the lightning director once the flash has been drawn. The
    /// cue is written before the flag, and the render callback reads the flag
    /// first, so it never plays a half-written strike.
    func strikeThunder(_ strike: LightningStrike) {
        guard let synth else { return }
        synth.thunderCue = ThunderCue(strike)
        synth.thunderRequest = true
    }

    /// The wind ahead of a strike. Value first, flag last, as with thunder.
    func blowGust(strength: Double) {
        guard let synth else { return }
        synth.gustStrength = min(max(strength, 0), 1)
        synth.gustRequest = true
    }

    var isActive: Bool { isRunning }
}
