import SwiftUI

/// The window. Two columns: what you are listening to on the left, how it
/// behaves on the right.
///
/// The old popover had to hide its settings behind a disclosure triangle
/// because it was 332 points wide and anchored to the menu bar. A window has
/// room to show everything at once, which is most of the reason for having one.
struct MainWindowView: View {
    @ObservedObject var state: MixState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 214)
                .background(.ultraThinMaterial)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 440)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            transport
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 14)

            VStack(spacing: 4) {
                ForEach(Scene.allCases) { scene in
                    SceneRow(scene: scene, isActive: state.scene == scene) {
                        withAnimation(.easeOut(duration: 0.18)) { state.select(scene) }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 12)

            Divider()
            sleepTimer
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
        }
    }

    private var transport: some View {
        HStack(spacing: 11) {
            Button {
                state.isPlaying.toggle()
            } label: {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 31, weight: .light))
                    .foregroundStyle(state.isPlaying ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(state.isPlaying ? "Pause" : "Resume")

            VStack(alignment: .leading, spacing: 2) {
                Text("Softfall")
                    .font(.system(size: 14, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusLine: String {
        if let notice = state.visualNotice { return notice }
        if let text = sleepText { return text }
        if !state.isPlaying { return "Paused" }
        if !state.current.isActive { return "Nothing playing" }
        return "Playing"
    }

    private var sleepText: String? {
        guard let end = state.sleepTimerEndsAt else { return nil }
        let remaining = max(0, end.timeIntervalSinceNow)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return minutes > 0 ? "Fading out in \(minutes)m" : "Fading out in \(seconds)s"
    }

    private var sleepTimer: some View {
        Menu {
            Button("Off") { state.sleepTimerEndsAt = nil }
            Divider()
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("\(minutes) minutes") {
                    state.sleepTimerEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
                }
            }
        } label: {
            Label(state.sleepTimerEndsAt == nil ? "Sleep timer" : "Timer on", systemImage: "moon.zzz")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 11.5))
    }

    // MARK: Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                thisScene
                ducking
                appearance
                displays
                behaviour
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var thisScene: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel(state.scene.title)

            // Two switches, not one. Rain on screen in silence and rain in
            // your ears with a still desktop are both things people want.
            HStack(spacing: 8) {
                SwitchTile(
                    title: "Picture",
                    symbol: state.current.picture ? "eye.fill" : "eye.slash",
                    isOn: state.current.picture
                ) {
                    state.updateCurrent { $0.picture.toggle() }
                }
                SwitchTile(
                    title: "Sound",
                    symbol: state.current.sound ? "speaker.wave.2.fill" : "speaker.slash",
                    isOn: state.current.sound
                ) {
                    state.updateCurrent { $0.sound.toggle() }
                }
            }
            .frame(maxWidth: 330)

            SliderRow(
                title: "Amount",
                symbol: "slider.horizontal.3",
                range: 0.02...1,
                value: Binding(
                    get: { state.current.level },
                    set: { v in state.updateCurrent { $0.level = v } }
                ),
                trailing: "\(Int(state.current.level * 100))%"
            )

            SliderRow(
                title: "Volume",
                symbol: state.masterVolume < 0.01 ? "speaker.slash" : "speaker.wave.2",
                range: 0...1,
                value: $state.masterVolume,
                trailing: "\(Int(state.masterVolume * 100))%"
            )

            // Only rain and thunder run the rain voice; a campfire has no use
            // for it, so the control is not offered there.
            if state.scene != .campfire {
                SliderRow(
                    title: "Rain tone",
                    symbol: "water.waves",
                    range: 0...1,
                    value: $state.rainTone,
                    trailing: "\(Int(state.rainTone * 100))%"
                )
                .help("Left is rain heard through a closed window. Right opens it.")
            }
        }
    }

    /// Ported from the popover this window replaced. The controls came from
    /// the auto-ducking work on `develop`; deleting that panel must not delete
    /// the only way to reach them.
    private var ducking: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("When something else is playing")
            Toggle("Quieten during calls", isOn: $state.duckOnCalls)
                .help("Fades down whenever the microphone goes live, and back up afterwards.")
            Toggle("Quieten while music plays", isOn: $state.duckOnMusic)
                .help("Follows Apple Music and Spotify.")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 11.5))
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel("Appearance")

            Picker("", selection: $state.placement) {
                ForEach(OverlayPlacement.allCases) { placement in
                    Text(placement.title).tag(placement)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 330)

            Text(state.placement.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            SliderRow(
                title: "Visibility",
                symbol: "circle.lefthalf.filled",
                range: 0.15...1,
                value: $state.opacity,
                trailing: "\(Int(state.opacity * 100))%"
            )

            SliderRow(
                title: "Rain colour",
                symbol: "drop.fill",
                range: 0...1,
                value: $state.rainBlue,
                trailing: "\(Int(state.rainBlue * 100))%"
            )
            .help("White at the left, cold blue at the right. How far you can go depends on the wallpaper behind it.")

            HStack(spacing: 9) {
                Image(systemName: "speedometer")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
                Text("Frame rate")
                    .font(.system(size: 11.5))
                    .frame(width: 72, alignment: .leading)
                Picker("", selection: $state.frameRate) {
                    ForEach(RainFrameRate.allCases) { rate in
                        Text(rate.title).tag(rate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 230)
                Spacer(minLength: 0)
            }
            .help("Lower is cheaper. Thirty still reads as continuous motion.")

            Toggle("Calm mode", isOn: $state.calmMode)
                .help("Fewer drops, slower fall, softer contrast.")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 11.5))
    }

    private var displays: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Displays")
            Toggle("Show on all displays", isOn: $state.allDisplays)
            Toggle("Hide over full-screen apps", isOn: $state.pauseVisualsWhenFullScreen)
                .help("Leaves films, presentations and full-screen editors untouched.")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 11.5))
    }

    private var behaviour: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Behaviour")
            Toggle("Pause animation on battery", isOn: $state.pauseVisualsOnBattery)
                .help("Off by default. Sound always keeps playing.")
            Toggle("Open at login", isOn: $state.launchAtLogin)
            Toggle("Open this window at launch", isOn: $state.openWindowAtLaunch)
                .help("Turn this off if you only want the menu bar icon when Softfall starts.")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 11.5))
    }
}
