import SwiftUI

/// Everything you set once and then forget.
///
/// Three tabs rather than one long scroll, because each pane then fits without
/// scrolling at all — and a settings window you never have to scroll is a
/// settings window you can scan.
struct SettingsView: View {
    @ObservedObject var state: MixState
    @ObservedObject var updater: Updater

    var body: some View {
        TabView {
            appearance
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            sound
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            behaviour
                .tabItem { Label("Behaviour", systemImage: "gearshape") }
        }
        // The Updates section only exists on a release build; give it the room.
        .frame(width: 470, height: updater.isAvailable ? 420 : 340)
    }

    // MARK: Appearance

    private var appearance: some View {
        Form {
            Section {
                Picker("Placement", selection: $state.placement) {
                    ForEach(OverlayPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(state.placement.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
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

            Section("Displays") {
                Toggle("Show on all displays", isOn: $state.allDisplays)
                Toggle("Hide over full-screen apps", isOn: $state.pauseVisualsWhenFullScreen)
                    .help("Leaves films, presentations and full-screen editors untouched. Turn this off to see weather over them.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Sound

    private var sound: some View {
        Form {
            Section {
                Slider(value: $state.rainTone, in: 0...1) {
                    Text("Rain tone")
                } minimumValueLabel: {
                    Image(systemName: "speaker.wave.1")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3")
                }
            } footer: {
                Text("Left is rain heard through a closed window. Right opens it.")
                    .foregroundStyle(.secondary)
            }

            Section("When something else is playing") {
                Toggle("Quieten during calls", isOn: $state.duckOnCalls)
                    .help("Fades down whenever the microphone goes live, and back up afterwards.")
                Toggle("Quieten while music plays", isOn: $state.duckOnMusic)
                    .help("Follows Apple Music and Spotify.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Behaviour

    private var behaviour: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $state.launchAtLogin)
                Toggle("Open the window at launch", isOn: $state.openWindowAtLaunch)
                    .help("Turn this off if you only want the menu bar icon when Softfall starts.")
            }

            Section {
                Toggle("Pause animation on battery", isOn: $state.pauseVisualsOnBattery)
            } footer: {
                Text("Off by default — being unplugged is not a request for an invisible app. Sound always keeps playing.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Hidden entirely on a build with no feed, rather than shown
            // disabled: a switch that can never do anything is a bug report.
            if updater.isAvailable {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                    HStack {
                        Text("Softfall \(updater.currentVersion)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Now") { updater.checkForUpdates(nil) }
                            .disabled(!updater.canCheck)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
