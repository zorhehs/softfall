import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var state: MixState!
    private var sound: SoundEngine!
    private var overlay: OverlayController!
    private var lightning: LightningDirector!
    private var power: PowerMonitor!
    private var menuBar: MenuBarController!
    private var window: MainWindowController!
    private var appMenu: AppMenuController!
    private var tickTimer: Timer?
    private var lastSceneKey: String?
    private var lastSuspend: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = MixState()
        sound = SoundEngine()
        overlay = OverlayController(state: state)
        sound.start()
        lightning = LightningDirector(state: state, overlay: overlay, sound: sound)

        power = PowerMonitor()
        power.onChange = { [weak self] in self?.applyPowerPolicy() }

        window = MainWindowController(state: state)

        // The menu bar item no longer owns a popover — it opens the window, or
        // offers the quick menu on a right-click.
        menuBar = MenuBarController(
            state: state,
            onOpenWindow: { [weak self] in self?.window.toggle() },
            onQuit: { NSApp.terminate(nil) }
        )

        appMenu = AppMenuController(state: state) { [weak self] in self?.window.show() }
        appMenu.install()

        state.onChange = { [weak self] in self?.stateChanged() }

        // One low-frequency timer drives the sleep-timer fade. Everything else
        // is event-driven, so an idle Softfall wakes the CPU about once a second.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tickTimer?.tolerance = 0.25

        applyPowerPolicy()
        stateChanged()

        if state.openWindowAtLaunch {
            window.show()
        }
    }

    /// Clicking the Dock icon of a running app sends this. Without it the click
    /// does nothing at all once the window has been closed, which looks broken.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window?.show()
        return true
    }

    /// Closing the window puts Softfall back to being just a menu bar icon. It
    /// is an ambient app; the weather should not stop because you tidied up.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

        // Restart the storm schedule only when something that affects it
        // changed, so adjusting an unrelated setting never resets the timing.
        let key = "\(state.scene.rawValue)|\(state.current.level)|\(state.current.sound)|\(state.current.picture)"
        if key != lastSceneKey {
            lastSceneKey = key
            lightning.settingsChanged()
        }
    }

    private func applyPowerPolicy() {
        guard let state, let power, let overlay else { return }

        // Sound is never suspended for power — it is the quiet part and costs
        // almost nothing. Only the animation is ever affected.
        //
        // Low Power Mode thins the scene rather than stopping it. Hiding the
        // picture outright with no explanation is how an ambient app gets
        // mistaken for a broken one.
        let batterySaver = state.pauseVisualsOnBattery && power.onBattery
        let suspend = power.shouldSuspendVisuals || batterySaver

        if state.powerSaving != power.lowPowerMode {
            state.powerSaving = power.lowPowerMode
        }

        let notice: String?
        if power.screenLocked {
            notice = nil                                  // nobody is looking
        } else if power.displaysAsleep {
            notice = nil
        } else if batterySaver {
            notice = "Animation paused on battery"
        } else if power.lowPowerMode {
            notice = "Thinned out for Low Power Mode"
        } else {
            notice = nil
        }

        // Assigning an identical value to a @Published property still fires
        // objectWillChange, which would loop straight back into here.
        if state.visualNotice != notice {
            state.visualNotice = notice
        }

        // Worth a line in the console: "I can see nothing on screen" should
        // always have a findable answer.
        if lastSuspend != suspend {
            lastSuspend = suspend
            if suspend {
                NSLog("Softfall: animation suspended (battery: \(power.onBattery), low power: \(power.lowPowerMode), display asleep: \(power.displaysAsleep), locked: \(power.screenLocked))")
            } else {
                NSLog("Softfall: animation running")
            }
        }

        overlay.setSuspended(suspend)
    }

    private func tick() {
        guard let state else { return }

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
