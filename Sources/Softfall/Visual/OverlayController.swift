import AppKit

/// Owns one overlay window per display and keeps them in step with the mix.
final class OverlayController {

    private struct Screen {
        let window: OverlayWindow
        let scene: SceneLayers
    }

    private var screens: [CGDirectDisplayID: Screen] = [:]
    private weak var state: MixState?
    private var suspended = false
    /// Reapplying the window level and collection behaviour on every state
    /// change makes windows flicker while a slider is being dragged, so the
    /// last applied configuration is remembered.
    private var appliedPlacement: OverlayPlacement?
    private var appliedFullScreenPolicy: Bool?

    init(state: MixState) {
        self.state = state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        rebuild()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Windows

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        // deviceDescription hands back an NSNumber; go through it explicitly
        // rather than relying on a bridged cast straight to UInt32.
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    private var targetScreens: [NSScreen] {
        guard let state else { return [] }
        if state.allDisplays { return NSScreen.screens }
        if let main = NSScreen.main { return [main] }
        return Array(NSScreen.screens.prefix(1))
    }

    @objc private func screenLayoutChanged() {
        appliedPlacement = nil
        appliedFullScreenPolicy = nil
        rebuild()
        refresh()
    }

    private func rebuild() {
        let wanted = targetScreens
        var wantedIDs = Set<CGDirectDisplayID>()

        for screen in wanted {
            guard let id = displayID(of: screen) else { continue }
            wantedIDs.insert(id)

            if let existing = screens[id] {
                // A display can be rearranged or change resolution while we
                // are running; move and re-lay-out rather than recreating.
                if existing.window.frame != screen.frame {
                    existing.window.setFrame(screen.frame, display: true)
                    existing.window.contentView?.frame = CGRect(origin: .zero, size: screen.frame.size)
                    existing.scene.resize(to: screen.frame.size)
                    attach(existing.scene, to: existing.window)
                }
                continue
            }

            let window = OverlayWindow(screen: screen)
            if let state {
                window.configure(
                    placement: state.placement,
                    showOverFullScreenApps: !state.pauseVisualsWhenFullScreen
                )
            }
            let scene = SceneLayers()
            scene.build(size: screen.frame.size)
            attach(scene, to: window)
            window.orderFrontRegardless()
            screens[id] = Screen(window: window, scene: scene)
        }

        // Tear down windows for displays that went away or were deselected.
        for (id, screen) in screens where !wantedIDs.contains(id) {
            screen.window.orderOut(nil)
            screen.window.close()
            screens.removeValue(forKey: id)
        }
    }

    private func attach(_ scene: SceneLayers, to window: OverlayWindow) {
        guard let host = window.contentView?.layer else { return }
        if scene.root.superlayer !== host {
            scene.root.removeFromSuperlayer()
            host.addSublayer(scene.root)
        }
        scene.root.frame = CGRect(origin: .zero, size: window.frame.size)
    }

    // MARK: Drive

    func refresh() {
        guard let state else { return }

        if targetScreens.count != screens.count { rebuild() }

        // Wind drives the slant of rain and snow. If the breeze is audible
        // but hidden, it still bends the weather — just by less, so the
        // picture never contradicts what you can hear.
        let wind = state.settings(.wind)
        var windLevel = 0.0
        if state.effectiveDensity(.wind) > 0 {
            windLevel = wind.level
        } else if wind.sound && state.isPlaying {
            windLevel = wind.level * 0.5
        }

        let visible = !suspended && state.anyVisualActive
        let fullScreenPolicy = !state.pauseVisualsWhenFullScreen
        let needsConfigure = appliedPlacement != state.placement
            || appliedFullScreenPolicy != fullScreenPolicy
        appliedPlacement = state.placement
        appliedFullScreenPolicy = fullScreenPolicy

        for (_, screen) in screens {
            if needsConfigure {
                screen.window.configure(
                    placement: state.placement,
                    showOverFullScreenApps: fullScreenPolicy
                )
            }
            screen.scene.update(state: state, windLevel: windLevel)

            if visible {
                if !screen.window.isVisible { screen.window.orderFrontRegardless() }
            } else if screen.window.isVisible {
                screen.window.orderOut(nil)
            }
        }
    }

    /// Hard stop for visuals — display asleep, screen locked, or the user
    /// asked to conserve battery. Windows are ordered out entirely so the
    /// compositor does no work at all.
    func setSuspended(_ value: Bool) {
        guard value != suspended else { return }
        suspended = value
        refresh()
    }

    func flashLightning(distance: Double) {
        guard let state, state.isPlaying, !suspended else { return }
        guard state.settings(.thunder).visual else { return }
        for (_, screen) in screens {
            screen.scene.flashLightning(distance: distance, opacityScale: state.opacity)
        }
    }

    func tearDown() {
        for (_, screen) in screens {
            screen.window.orderOut(nil)
            screen.window.close()
        }
        screens.removeAll()
    }
}

/// Decides when lightning happens, draws it, and hands the thunder to the
/// audio engine a realistic moment later.
///
/// Splitting it this way is the whole reason the storm feels real: light
/// arrives instantly, sound takes about three seconds per kilometre, and the
/// gap between them is what your ear reads as distance.
final class LightningDirector {

    private weak var state: MixState?
    private weak var overlay: OverlayController?
    private weak var sound: SoundEngine?
    private var timer: Timer?
    private var rng = SystemRandomNumberGenerator()

    init(state: MixState, overlay: OverlayController, sound: SoundEngine) {
        self.state = state
        self.overlay = overlay
        self.sound = sound
        scheduleNext()
    }

    deinit { timer?.invalidate() }

    private func scheduleNext() {
        timer?.invalidate()
        guard let state else { return }

        let settings = state.settings(.thunder)
        let active = state.isPlaying && (settings.visual || settings.sound) && settings.level > 0.01
        guard active else {
            // Idle poll — cheap, and picks the storm straight back up when
            // thunder is switched on.
            timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                self?.scheduleNext()
            }
            return
        }

        // A gentle setting means rare, far-off rumbles; a high one means a
        // storm more or less on top of you.
        let level = settings.level
        let minGap = lerp(52, 5, level)
        let maxGap = lerp(150, 17, level)
        let gap = Double.random(in: minGap...maxGap, using: &rng)

        timer = Timer.scheduledTimer(withTimeInterval: gap, repeats: false) { [weak self] _ in
            self?.strike()
        }
        timer?.tolerance = 1.0
    }

    private func strike() {
        guard let state, state.isPlaying else { scheduleNext(); return }
        let settings = state.settings(.thunder)

        // Higher intensity pulls the storm closer, but never all the way —
        // a little distance is what keeps thunder pleasant rather than startling.
        let nearest = max(0.10, 1.0 - settings.level)
        let distance = Double.random(in: nearest...1.0, using: &rng)

        overlay?.flashLightning(distance: distance)

        guard settings.sound else { scheduleNext(); return }

        // Roughly three seconds per kilometre, scaled into our 0...1 range.
        let delay = 0.18 + distance * 4.6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let state = self.state, state.isPlaying,
                  state.settings(.thunder).sound else { return }
            self.sound?.strikeThunder(distance: distance)
        }

        scheduleNext()
    }

    /// Called when thunder settings change so the next strike reflects them.
    func settingsChanged() {
        scheduleNext()
    }
}
