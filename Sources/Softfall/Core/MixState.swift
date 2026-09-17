import Foundation
import Combine

enum OverlayPlacement: String, Codable, CaseIterable, Identifiable {
    /// Drawn above your windows, click-through. The classic look.
    case aboveWindows
    /// Drawn on the desktop, behind every window. Far less distracting —
    /// you only see weather in the gaps between what you're working on.
    case behindWindows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aboveWindows:  return "Above windows"
        case .behindWindows: return "Behind windows"
        }
    }

    var detail: String {
        switch self {
        case .aboveWindows:  return "Weather falls over everything. Clicks pass straight through."
        case .behindWindows: return "Weather stays on the desktop, visible only around your windows."
        }
    }
}

/// Everything the user can change, in one observable place.
final class MixState: ObservableObject {

    // MARK: Scene

    @Published var scene: Scene = .rain
    /// Kept per scene, so switching away and back restores what you had.
    @Published var settings: [Scene: SceneSettings] = MixState.defaultSettings
    @Published var isPlaying: Bool = true
    @Published var masterVolume: Double = 0.7

    // MARK: Presentation

    @Published var placement: OverlayPlacement = .aboveWindows
    @Published var allDisplays: Bool = true
    /// Fewer particles, slower movement, softer contrast.
    @Published var calmMode: Bool = false
    @Published var opacity: Double = 0.85

    // MARK: Behaviour

    @Published var pauseVisualsWhenFullScreen: Bool = true
    /// Off by default. Being unplugged is not a request for an invisible app.
    @Published var pauseVisualsOnBattery: Bool = false
    @Published var launchAtLogin: Bool = false
    /// Whether the window opens on launch. Worth its own switch: an app that
    /// opens at login should not throw a window at you every morning.
    @Published var openWindowAtLaunch: Bool = true

    /// Set when Low Power Mode is on. Thins the scene rather than hiding it.
    @Published var powerSaving: Bool = false
    /// Why the picture has stopped, when it has.
    @Published var visualNotice: String?

    // MARK: Sleep timer (not persisted — a timer should never outlive a launch)

    @Published var sleepTimerEndsAt: Date?
    @Published var fadeMultiplier: Double = 1.0

    // MARK: Wiring

    var onChange: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private static let storageKey = "softfall.state.v3"

    init() {
        load()

        // objectWillChange fires *before* the mutation, so hop to the next
        // runloop turn to read settled values.
        objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.onChange?() }
            }
            .store(in: &cancellables)

        objectWillChange
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    // MARK: Current scene

    var current: SceneSettings {
        settings[scene] ?? SceneSettings()
    }

    func updateCurrent(_ transform: (inout SceneSettings) -> Void) {
        var s = current
        transform(&s)
        settings[scene] = s
    }

    /// Audio gain for one engine layer, derived from the chosen scene.
    /// A layer the current scene does not use is simply silent.
    func effectiveGain(_ layer: Layer) -> Double {
        guard isPlaying, current.sound, scene.layers.contains(layer) else { return 0 }
        return current.level * scene.weight(for: layer) * masterVolume * fadeMultiplier
    }

    /// Particle density for one engine layer.
    func effectiveDensity(_ layer: Layer) -> Double {
        guard isPlaying, current.picture, scene.layers.contains(layer) else { return 0 }
        var d = current.level * scene.weight(for: layer)
        if calmMode { d *= 0.45 }
        if powerSaving { d *= 0.5 }
        return d
    }

    /// The level fed to a layer's synthesiser as a timbre control, independent
    /// of how loud it is.
    func level(_ layer: Layer) -> Double {
        scene.layers.contains(layer) ? current.level : 0.5
    }

    var anyVisualActive: Bool {
        isPlaying && current.picture && current.level > 0.001
    }

    func select(_ newScene: Scene) {
        scene = newScene
        isPlaying = true
    }

    // MARK: Persistence

    private struct Stored: Codable {
        var scene: Scene
        var settings: [String: SceneSettings]
        var isPlaying: Bool
        var masterVolume: Double
        var placement: OverlayPlacement
        var allDisplays: Bool
        var calmMode: Bool
        var opacity: Double
        var pauseVisualsOnBattery: Bool
        var pauseVisualsWhenFullScreen: Bool
        var launchAtLogin: Bool
        /// Optional on purpose. A non-optional field added to this struct makes
        /// every previously saved blob fail to decode, which silently resets
        /// all of someone's settings on upgrade.
        var openWindowAtLaunch: Bool?
    }

    func save() {
        var dict: [String: SceneSettings] = [:]
        for (key, value) in settings { dict[key.rawValue] = value }
        let stored = Stored(
            scene: scene,
            settings: dict,
            isPlaying: isPlaying,
            masterVolume: masterVolume,
            placement: placement,
            allDisplays: allDisplays,
            calmMode: calmMode,
            opacity: opacity,
            pauseVisualsOnBattery: pauseVisualsOnBattery,
            pauseVisualsWhenFullScreen: pauseVisualsWhenFullScreen,
            launchAtLogin: launchAtLogin,
            openWindowAtLaunch: openWindowAtLaunch
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }

        var restored = MixState.defaultSettings
        for (key, value) in stored.settings {
            if let s = Scene(rawValue: key) { restored[s] = value }
        }
        settings = restored
        scene = stored.scene
        isPlaying = stored.isPlaying
        masterVolume = stored.masterVolume
        placement = stored.placement
        allDisplays = stored.allDisplays
        calmMode = stored.calmMode
        opacity = stored.opacity
        pauseVisualsOnBattery = stored.pauseVisualsOnBattery
        pauseVisualsWhenFullScreen = stored.pauseVisualsWhenFullScreen
        launchAtLogin = stored.launchAtLogin
        openWindowAtLaunch = stored.openWindowAtLaunch ?? true
    }

    static var defaultSettings: [Scene: SceneSettings] {
        [
            .rain:     SceneSettings(picture: true, sound: true, level: 0.45),
            .thunder:  SceneSettings(picture: true, sound: true, level: 0.55),
            .campfire: SceneSettings(picture: true, sound: true, level: 0.55)
        ]
    }
}
