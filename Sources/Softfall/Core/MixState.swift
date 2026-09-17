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

    @Published var layers: [Layer: LayerSettings] = MixState.defaultLayers
    @Published var isPlaying: Bool = true
    @Published var masterVolume: Double = 0.7

    // MARK: Presentation

    @Published var placement: OverlayPlacement = .aboveWindows
    @Published var allDisplays: Bool = true
    /// Caps particle count and speed, and softens contrast. For when even
    /// gentle motion is too much — and it is also the low-power path.
    @Published var calmMode: Bool = false
    @Published var opacity: Double = 0.85

    // MARK: Behaviour

    /// Off by default. Being unplugged is not a request for an invisible app,
    /// and defaulting this on made Softfall look broken on any laptop that
    /// happened not to be charging.
    @Published var pauseVisualsOnBattery: Bool = false
    @Published var pauseVisualsWhenFullScreen: Bool = true
    @Published var launchAtLogin: Bool = false

    // MARK: Sleep timer (not persisted — a timer should never outlive a launch)

    @Published var sleepTimerEndsAt: Date?
    @Published var fadeMultiplier: Double = 1.0

    // MARK: Wiring

    /// Called (on main) whenever anything changes, after the change lands.
    var onChange: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    // Bumped from v1: the battery default changed, and a saved `true` from an
    // earlier run would otherwise keep overriding it. Settings are cheap to
    // set again at this stage; a mystifying invisible app is not.
    private static let storageKey = "softfall.state.v2"

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

    // MARK: Convenience

    func settings(_ layer: Layer) -> LayerSettings {
        layers[layer] ?? LayerSettings()
    }

    func update(_ layer: Layer, _ transform: (inout LayerSettings) -> Void) {
        var s = settings(layer)
        transform(&s)
        layers[layer] = s
    }

    /// Anything audible right now, accounting for master state and fade.
    func effectiveGain(_ layer: Layer) -> Double {
        guard isPlaying, layer.hasAudio else { return 0 }
        return settings(layer).audioGain * masterVolume * fadeMultiplier
    }

    /// Anything visible right now.
    func effectiveDensity(_ layer: Layer) -> Double {
        guard isPlaying, layer.hasVisual else { return 0 }
        var d = settings(layer).visualDensity
        if calmMode { d *= 0.45 }
        if powerSaving { d *= 0.5 }
        return d
    }

    var anyVisualActive: Bool {
        isPlaying && Layer.allCases.contains { $0.hasVisual && settings($0).visual && settings($0).level > 0.001 }
    }

    var activeCount: Int {
        Layer.allCases.filter { settings($0).isActive }.count
    }

    // MARK: Presets

    func apply(_ preset: Preset) {
        var next: [Layer: LayerSettings] = [:]
        for layer in Layer.allCases {
            next[layer] = preset.layers[layer] ?? LayerSettings(visual: false, sound: false, level: 0.5)
        }
        layers = next
        isPlaying = true
    }

    func matches(_ preset: Preset) -> Bool {
        for layer in Layer.allCases {
            let mine = settings(layer)
            let theirs = preset.layers[layer] ?? LayerSettings(visual: false, sound: false, level: 0.5)
            if mine.visual != theirs.visual || mine.sound != theirs.sound { return false }
            if mine.isActive && abs(mine.level - theirs.level) > 0.02 { return false }
        }
        return true
    }

    func silenceAll() {
        for layer in Layer.allCases {
            update(layer) { $0.visual = false; $0.sound = false }
        }
    }

    // MARK: Persistence

    private struct Stored: Codable {
        var layers: [String: LayerSettings]
        var isPlaying: Bool
        var masterVolume: Double
        var placement: OverlayPlacement
        var allDisplays: Bool
        var calmMode: Bool
        var opacity: Double
        var pauseVisualsOnBattery: Bool
        var pauseVisualsWhenFullScreen: Bool
        var launchAtLogin: Bool
    }

    func save() {
        var dict: [String: LayerSettings] = [:]
        for (layer, settings) in layers { dict[layer.rawValue] = settings }
        let stored = Stored(
            layers: dict,
            isPlaying: isPlaying,
            masterVolume: masterVolume,
            placement: placement,
            allDisplays: allDisplays,
            calmMode: calmMode,
            opacity: opacity,
            pauseVisualsOnBattery: pauseVisualsOnBattery,
            pauseVisualsWhenFullScreen: pauseVisualsWhenFullScreen,
            launchAtLogin: launchAtLogin
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }

        var restored: [Layer: LayerSettings] = MixState.defaultLayers
        for (key, value) in stored.layers {
            if let layer = Layer(rawValue: key) { restored[layer] = value }
        }
        layers = restored
        isPlaying = stored.isPlaying
        masterVolume = stored.masterVolume
        placement = stored.placement
        allDisplays = stored.allDisplays
        calmMode = stored.calmMode
        opacity = stored.opacity
        pauseVisualsOnBattery = stored.pauseVisualsOnBattery
        pauseVisualsWhenFullScreen = stored.pauseVisualsWhenFullScreen
        launchAtLogin = stored.launchAtLogin
    }

    /// First launch lands on gentle rain — the thing almost everyone opens
    /// this kind of app for — rather than an empty screen.
    static var defaultLayers: [Layer: LayerSettings] {
        var d: [Layer: LayerSettings] = [:]
        for layer in Layer.allCases {
            d[layer] = LayerSettings(visual: false, sound: false, level: 0.5)
        }
        d[.rain] = LayerSettings(visual: true, sound: true, level: 0.45)
        d[.fog] = LayerSettings(visual: true, sound: false, level: 0.25)
        return d
    }
}
