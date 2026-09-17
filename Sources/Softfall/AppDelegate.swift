import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var state: MixState!
    private var sound: SoundEngine!
    private var overlay: OverlayController!
    private var lightning: LightningDirector!
    private var power: PowerMonitor!
    private var ducker: AudioDucker!
    private var menuBar: MenuBarController!
    private var tickTimer: Timer?
    private var lastThunderSettings: LayerSettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = MixState()
        sound = SoundEngine()
        overlay = OverlayController(state: state)
        sound.start()
        lightning = LightningDirector(state: state, overlay: overlay, sound: sound)

        power = PowerMonitor()
        power.onChange = { [weak self] in self?.applyPowerPolicy() }

        ducker = AudioDucker()
        ducker.onChange = { [weak self] in
            guard let self, let state = self.state else { return }
            state.duckMultiplier = self.ducker.multiplier
            // Only the audio needs updating during a fade; the picture and the
            // rest of the UI are unaffected by ducking.
            self.sound.apply(state)
        }
        ducker.onStateChange = { [weak self] in
            guard let self, let state = self.state else { return }
            state.isDucked = self.ducker.isDucking
        }

        menuBar = MenuBarController(state: state) {
            NSApp.terminate(nil)
        }

        state.onChange = { [weak self] in self?.stateChanged() }

        // One low-frequency timer drives the sleep-timer fade. Everything else
        // is event-driven, so an idle Softfall wakes the CPU about once a second.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tickTimer?.tolerance = 0.25

        applyPowerPolicy()
        stateChanged()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.save()
        tickTimer?.invalidate()
        sound?.stop()
        overlay?.tearDown()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Wiring

    private func stateChanged() {
        sound.apply(state)
        overlay.refresh()
        menuBar.updateIcon()
        applyPowerPolicy()
        syncLoginItem()
        ducker.duckForCalls = state.duckOnCalls
        ducker.duckForMusic = state.duckOnMusic

        // Restart the storm schedule only when thunder itself changed, so
        // adjusting an unrelated slider never resets the timing.
        let thunder = state.settings(.thunder)
        if thunder != lastThunderSettings {
            lastThunderSettings = thunder
            lightning.settingsChanged()
        }
    }

    private func applyPowerPolicy() {
        guard let state, let power, let overlay else { return }

        // Sound is never suspended for power — it is the quiet part and costs
        // almost nothing. Only the animation stops.
        let batterySaver = state.pauseVisualsOnBattery && (power.onBattery || power.lowPowerMode)
        overlay.setSuspended(power.shouldSuspendVisuals || batterySaver)
    }

    private func tick() {
        guard let state else { return }

        // The microphone check rides on this existing timer rather than
        // starting one of its own.
        ducker.poll()

        guard let end = state.sleepTimerEndsAt else {
            if state.fadeMultiplier != 1.0 {
                state.fadeMultiplier = 1.0
                sound.apply(state)
            }
            return
        }

        let remaining = end.timeIntervalSinceNow

        if remaining <= 0 {
            state.sleepTimerEndsAt = nil
            state.fadeMultiplier = 1.0
            state.isPlaying = false
            return
        }

        // Fade across the final two minutes rather than cutting out. Waking to
        // silence should feel like the rain moved on, not like a switch flipped.
        let fadeWindow: TimeInterval = 120
        let fade = remaining < fadeWindow ? max(0, remaining / fadeWindow) : 1.0
        if abs(fade - state.fadeMultiplier) > 0.002 {
            state.fadeMultiplier = fade
            sound.apply(state)
        }
    }

    private func syncLoginItem() {
        let service = SMAppService.mainApp
        let wanted = state.launchAtLogin
        let enabled = service.status == .enabled
        guard wanted != enabled else { return }

        do {
            if wanted {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("Softfall: could not update the login item — \(error.localizedDescription)")
        }
    }
}
