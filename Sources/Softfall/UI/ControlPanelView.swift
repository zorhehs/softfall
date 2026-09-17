import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var state: MixState
    @State private var showSettings = false
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    scenes
                    controls
                    settings
                }
                .padding(16)
            }
            .frame(maxHeight: 420)

            Divider()
            footer
        }
        .frame(width: 332)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                state.isPlaying.toggle()
            } label: {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(state.isPlaying ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(state.isPlaying ? "Pause" : "Resume")

            VStack(alignment: .leading, spacing: 3) {
                Text("Softfall")
                    .font(.system(size: 14, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: state.masterVolume < 0.01 ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Slider(value: $state.masterVolume, in: 0...1)
                    .controlSize(.small)
                    .frame(width: 80)
            }
            .help("Overall volume")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    // MARK: Scenes

    private var scenes: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Scene")
            HStack(spacing: 8) {
                ForEach(Scene.allCases) { scene in
                    SceneButton(scene: scene, isActive: state.scene == scene) {
                        withAnimation(.easeOut(duration: 0.18)) { state.select(scene) }
                    }
                }
            }
        }
    }

    // MARK: Picture / sound

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Amount")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(state.current.level * 100))%")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Slider(
                    value: Binding(
                        get: { state.current.level },
                        set: { v in state.updateCurrent { $0.level = v } }
                    ),
                    in: 0.02...1
                )
                .controlSize(.small)
            }
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showSettings.toggle() }
            } label: {
                HStack(spacing: 6) {
                    SectionLabel("Settings")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showSettings ? 90 : 0))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSettings {
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("", selection: $state.placement) {
                            ForEach(OverlayPlacement.allCases) { placement in
                                Text(placement.title).tag(placement)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(state.placement.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text("Visibility")
                            .font(.system(size: 11))
                            .frame(width: 58, alignment: .leading)
                        Slider(value: $state.opacity, in: 0.15...1)
                            .controlSize(.small)
                    }

                    Toggle("Smoother motion", isOn: $state.highFrameRate)
                        .help("Asks the system for a higher frame rate. Only does anything on a display that can show one, and costs more power.")
                    Toggle("Calm mode", isOn: $state.calmMode)
                        .help("Fewer particles, softer contrast.")
                    Toggle("Show on all displays", isOn: $state.allDisplays)
                    Toggle("Hide over full-screen apps", isOn: $state.pauseVisualsWhenFullScreen)
                        .help("Leaves films, presentations and full-screen editors untouched.")
                    Toggle("Pause animation on battery", isOn: $state.pauseVisualsOnBattery)
                        .help("Off by default. Sound always keeps playing.")
                    Toggle("Open at login", isOn: $state.launchAtLogin)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Off") { state.sleepTimerEndsAt = nil }
                Divider()
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        state.sleepTimerEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
                    }
                }
            } label: {
                Label(state.sleepTimerEndsAt == nil ? "Sleep timer" : "Timer on",
                      systemImage: "moon.zzz")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.system(size: 11))

            Spacer()

            Button("Quit", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Components

private struct SceneButton: View {
    let scene: Scene
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: scene.symbol)
                    .font(.system(size: 17, weight: .light))
                Text(scene.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
        .help(scene.blurb)
    }
}

private struct SwitchTile: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: isOn ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(isOn ? "\(title) is on" : "\(title) is off")
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
