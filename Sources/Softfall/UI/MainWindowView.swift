import SwiftUI

/// The window.
///
/// Built out of the platform's own two-column idiom rather than a hand-rolled
/// one: `NavigationSplitView` with a real sidebar `List`, and a grouped `Form`
/// for everything else. The first version of this window stacked VStacks and
/// aligned its own label columns to a fixed 72 points, which meant
/// reimplementing — badly — what a `Form` already does: consistent label and
/// control alignment, correct spacing, grouped boxes, and the look people
/// already know from System Settings.
///
/// Using the real sidebar also brings selection that follows the accent colour
/// and window focus, keyboard navigation between scenes, and the collapse
/// button in the title bar. None of that was worth writing by hand.
struct MainWindowView: View {
    @ObservedObject var state: MixState

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 176, ideal: 196, max: 240)
        } detail: {
            detail
                .navigationTitle("Softfall")
                .navigationSubtitle(statusLine)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.isPlaying.toggle()
                } label: {
                    Label(state.isPlaying ? "Pause" : "Play",
                          systemImage: state.isPlaying ? "pause.fill" : "play.fill")
                }
                .help(state.isPlaying ? "Pause" : "Resume")
            }
        }
        .frame(minWidth: 660, minHeight: 460)
    }

    // MARK: Sidebar

    /// `List` selection is optional by nature — nothing selected is a state it
    /// has to be able to express — while the app always has a scene. The
    /// adapter keeps that difference from leaking into `MixState`.
    private var selection: Binding<Scene?> {
        Binding(
            get: { state.scene },
            set: { if let scene = $0 { state.select(scene) } }
        )
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section("Scenes") {
                ForEach(Scene.allCases) { scene in
                    Label(scene.title, systemImage: scene.symbol)
                        .tag(scene as Scene?)
                        .help(scene.blurb)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var statusLine: String {
        if let notice = state.visualNotice { return notice }
        if let text = sleepText { return text }
        if !state.isPlaying { return "Paused" }
        if !state.current.isActive { return "Nothing playing" }
        return state.scene.blurb
    }

    private var sleepText: String? {
        guard let end = state.sleepTimerEndsAt else { return nil }
        let remaining = max(0, end.timeIntervalSinceNow)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return minutes > 0 ? "Fading out in \(minutes)m" : "Fading out in \(seconds)s"
    }

    // MARK: Detail

    private var detail: some View {
        Form {
            sceneSection
            appearanceSection
            displaysSection
            duckingSection
            behaviourSection
            sleepSection
        }
        .formStyle(.grouped)
    }

    private var sceneSection: some View {
        Section {
            // Two switches, not one. Rain on screen in silence and rain in
            // your ears over a still desktop are both things people want.
            Toggle("Picture", isOn: Binding(
                get: { state.current.picture },
                set: { v in state.updateCurrent { $0.picture = v } }
            ))
            Toggle("Sound", isOn: Binding(
                get: { state.current.sound },
                set: { v in state.updateCurrent { $0.sound = v } }
            ))

            Slider(
                value: Binding(
                    get: { state.current.level },
                    set: { v in state.updateCurrent { $0.level = v } }
                ),
                in: 0.02...1
            ) {
                Text("Amount")
            }

            Slider(value: $state.masterVolume, in: 0...1) {
                Text("Volume")
            }

            // Only rain and thunder run the rain voice; a campfire has no use
            // for it, so the control is not offered there.
            if state.scene != .campfire {
                Slider(value: $state.rainTone, in: 0...1) {
                    Text("Rain tone")
                } minimumValueLabel: {
                    Image(systemName: "speaker.wave.1")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3")
                }
                .help("Left is rain heard through a closed window. Right opens it.")
            }
        } header: {
            Text(state.scene.title)
        } footer: {
            Text(state.scene.blurb)
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Placement", selection: $state.placement) {
                ForEach(OverlayPlacement.allCases) { placement in
                    Text(placement.title).tag(placement)
                }
            }
            .pickerStyle(.segmented)

            Text(state.placement.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Slider(value: $state.opacity, in: 0.15...1) {
                Text("Visibility")
            }

            Slider(value: $state.rainBlue, in: 0...1) {
                Text("Rain colour")
            }
            .help("Left is white, right is a cold blue. How far it can go before it disappears depends on the wallpaper behind it.")

            Picker("Frame rate", selection: $state.frameRate) {
                ForEach(RainFrameRate.allCases) { rate in
                    Text(rate.title).tag(rate)
                }
            }
            .pickerStyle(.segmented)
            .help("Lower is cheaper. Thirty still reads as continuous motion.")

            Toggle("Calm mode", isOn: $state.calmMode)
                .help("Fewer drops, slower fall, softer contrast.")
        }
    }

    private var displaysSection: some View {
        Section("Displays") {
            Toggle("Show on all displays", isOn: $state.allDisplays)
            Toggle("Hide over full-screen apps", isOn: $state.pauseVisualsWhenFullScreen)
                .help("Leaves films, presentations and full-screen editors untouched. Turn this off to see weather over them.")
        }
    }

    /// From the auto-ducking work. The popover this window replaced was the
    /// only way to reach these, so they came across with it.
    private var duckingSection: some View {
        Section("When something else is playing") {
            Toggle("Quieten during calls", isOn: $state.duckOnCalls)
                .help("Fades down whenever the microphone goes live, and back up afterwards.")
            Toggle("Quieten while music plays", isOn: $state.duckOnMusic)
                .help("Follows Apple Music and Spotify.")
        }
    }

    private var behaviourSection: some View {
        Section("Behaviour") {
            Toggle("Pause animation on battery", isOn: $state.pauseVisualsOnBattery)
                .help("Off by default. Sound always keeps playing.")
            Toggle("Open at login", isOn: $state.launchAtLogin)
            Toggle("Open this window at launch", isOn: $state.openWindowAtLaunch)
                .help("Turn this off if you only want the menu bar icon when Softfall starts.")
        }
    }

    private var sleepSection: some View {
        Section {
            // A timer is an action rather than a setting: the remaining time
            // counts down, so there is no stable value for a picker to show.
            Menu {
                Button("Off") { state.sleepTimerEndsAt = nil }
                Divider()
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        state.sleepTimerEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
                    }
                }
            } label: {
                Label(state.sleepTimerEndsAt == nil ? "Set a sleep timer" : "Change the timer",
                      systemImage: "moon.zzz")
            }
            .fixedSize()
        } header: {
            Text("Sleep timer")
        } footer: {
            Text(sleepText ?? "Fades out across the last two minutes rather than cutting off.")
                .foregroundStyle(.secondary)
        }
    }
}
