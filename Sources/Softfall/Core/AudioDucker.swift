import Foundation
import AppKit
import CoreAudio

/// Gets out of the way when something more important starts making noise.
///
/// Two signals, both free and neither needing a permission prompt:
///
/// * **Calls** — the default input device going live. Any app that opens the
///   microphone trips this, so it covers Zoom, Meet, FaceTime, Teams, Slack
///   huddles, Discord and anything else, without maintaining a list of
///   bundle identifiers that would be out of date within a month.
/// * **Music** — the playback notifications Apple Music and Spotify broadcast.
///   These two specifically; there is no general "is anything playing" signal
///   available on macOS 13 that does not also see our own output.
final class AudioDucker {

    /// Multiply audio gain by this. 1.0 is normal, lower is ducked.
    private(set) var multiplier: Double = 1.0
    private(set) var isDucking = false

    /// Called whenever `multiplier` moves, including every step of a fade.
    var onChange: (() -> Void)?
    /// Called when ducking starts or stops, for anything that only cares about
    /// the transition rather than each frame of it.
    var onStateChange: (() -> Void)?

    var duckForCalls = true { didSet { updateTarget() } }
    var duckForMusic = true { didSet { updateTarget() } }

    /// How far down to pull it. Not to silence — hearing the rain drop away
    /// under a voice is more reassuring than having it vanish outright.
    var duckedLevel: Double = 0.16

    private var micLive = false
    private var musicLive = false
    private var target: Double = 1.0
    private var rampTimer: Timer?
    /// Block-based observers are identified by the token the call returns;
    /// passing `self` to removeObserver would not unregister them.
    private var observers: [NSObjectProtocol] = []

    init() {
        let centre = DistributedNotificationCenter.default()

        observers.append(centre.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handlePlayerInfo(note)
        })

        observers.append(centre.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handlePlayerInfo(note)
        })
    }

    deinit {
        rampTimer?.invalidate()
        let centre = DistributedNotificationCenter.default()
        for observer in observers { centre.removeObserver(observer) }
    }

    // MARK: Signals

    private func handlePlayerInfo(_ note: Notification) {
        // If the poster stripped userInfo we cannot tell play from pause, so
        // leave the current state alone rather than guessing wrong.
        guard let state = note.userInfo?["Player State"] as? String else { return }
        let playing = (state == "Playing")
        guard playing != musicLive else { return }
        musicLive = playing
        updateTarget()
    }

    /// Called once a second from the app's existing tick, so this adds no
    /// timer of its own and no extra wakeups.
    func poll() {
        let live = Self.defaultInputDeviceIsLive()
        guard live != micLive else { return }
        micLive = live
        updateTarget()
    }

    // MARK: Ramping

    private func updateTarget() {
        let shouldDuck = (duckForCalls && micLive) || (duckForMusic && musicLive)
        let newTarget = shouldDuck ? duckedLevel : 1.0
        guard newTarget != target else { return }
        target = newTarget

        if shouldDuck != isDucking {
            isDucking = shouldDuck
            onStateChange?()
        }
        startRamp()
    }

    private func startRamp() {
        rampTimer?.invalidate()

        // Down quickly so the first words of a call are not competing with
        // rain; back up slowly so the return is something you notice only if
        // you look for it.
        let duration = target < multiplier ? 0.7 : 2.6
        let interval = 1.0 / 30.0
        let steps = max(1, Int(duration / interval))
        var step = 0
        let start = multiplier
        let end = target

        rampTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            let t = min(1.0, Double(step) / Double(steps))
            // Smoothstep, so neither end of the fade has an audible corner.
            let eased = t * t * (3 - 2 * t)
            self.multiplier = start + (end - start) * eased
            self.onChange?()
            if t >= 1.0 {
                self.multiplier = end
                timer.invalidate()
                self.rampTimer = nil
            }
        }
        rampTimer?.tolerance = 0.005
    }

    // MARK: Core Audio

    /// True when the system's default input device is running — which is what
    /// "someone is on a call" looks like from outside the app.
    private static func defaultInputDeviceIsLive() -> Bool {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress, 0, nil, &deviceSize, &device
        )
        guard deviceStatus == noErr, device != AudioDeviceID(kAudioObjectUnknown) else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)

        let runningStatus = AudioObjectGetPropertyData(
            device, &runningAddress, 0, nil, &runningSize, &running
        )
        return runningStatus == noErr && running != 0
    }
}
