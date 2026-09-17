import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var state: MixState
    @State private var showMixer = false
    @State private var showSettings = false
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    presets
                    mixer
                    settings
                }
                .padding(16)
            }
            .frame(maxHeight: 460)

            Divider()
            footer
        }
        .frame(width: 348)
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
            .help(state.isPlaying ? "Pause everything" : "Resume")

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
                    .frame(width: 84)
            }
            .help("Overall volume")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusLine: String {
        if let text = sleepText { return text }
        if !state.isPlaying { return "Paused" }
        let count = state.activeCount
        if count == 0 { return "Nothing playing" }
        let active = Layer.allCases.filter { state.settings($0).isActive }
        return active.prefix(3).map(\.title).joined(separator: " · ")
            + (count > 3 ? " +\(count - 3)" : "")
    }

    private var sleepText: String? {
        guard let end = state.sleepTimerEndsAt else { return nil }
        let remaining = max(0, end.timeIntervalSinceNow)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return minutes > 0 ? "Fading out in \(minutes)m" : "Fading out in \(seconds)s"
    }

    // MARK: Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Scenes")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Preset.all) { preset in
                    PresetChip(preset: preset, isActive: state.matches(preset)) {
                        withAnimation(.easeOut(duration: 0.2)) { state.apply(preset) }
                    }
                }
            }
        }
    }

    // MARK: Mixer

    private var mixer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showMixer.toggle() }
            } label: {
                HStack(spacing: 6) {
                    SectionLabel("Mix")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showMixer ? 90 : 0))
                    Spacer()
                    if !showMixer {
                        Text("\(state.activeCount) on")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMixer {
                VStack(alignment: .leading, spacing: 14) {
                    // The two icon buttons on each row are the point: picture
                    // and sound are separate switches, so you can have rain you
                    // can only see, or rain you can only hear.
                    HStack(spacing: 0) {
                        Text("Picture and sound switch independently")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }

                    ForEach(LayerGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .tracking(0.6)
                            ForEach(group.layers) { layer in
                                LayerRow(layer: layer, state: state)
                            }
                        }
                    }

                    Button("Turn everything off") {
                        withAnimation(.easeOut(duration: 0.2)) { state.silenceAll() }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                VStack(alignment: .leading, spacing: 14) {
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

                    LabeledSlider(
                        title: "Visibility",
                        systemImage: "circle.lefthalf.filled",
                        value: $state.opacity
                    )

                    Toggle("Calm mode", isOn: $state.calmMode)
                        .help("Fewer particles, slower movement, softer contrast.")
                    Toggle("Show on all displays", isOn: $state.allDisplays)
                    Toggle("Hide over full-screen apps", isOn: $state.pauseVisualsWhenFullScreen)
                        .help("Leaves films, presentations and full-screen editors untouched.")
                    Toggle("Pause animation on battery", isOn: $state.pauseVisualsOnBattery)
                        .help("Off by default. Sound always keeps playing; only the animation stops.")
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

// MARK: - Row

private struct LayerRow: View {
    let layer: Layer
    @ObservedObject var state: MixState

    private var settings: LayerSettings { state.settings(layer) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: layer.symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(settings.isActive ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(layer.title)
                        .font(.system(size: 12, weight: settings.isActive ? .medium : .regular))
                    if settings.isActive {
                        Text(layer.subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                IconToggle(
                    on: settings.visual,
                    enabled: layer.hasVisual,
                    onSymbol: "eye.fill",
                    offSymbol: "eye.slash",
                    help: layer.hasVisual ? "Show on screen" : "This layer has no picture"
                ) {
                    state.update(layer) { $0.visual.toggle() }
                }

                IconToggle(
                    on: settings.sound,
                    enabled: layer.hasAudio,
                    onSymbol: "speaker.wave.2.fill",
                    offSymbol: "speaker.slash",
                    help: layer.hasAudio ? "Play its sound" : "This layer has no sound"
                ) {
                    state.update(layer) { $0.sound.toggle() }
                }
            }

            if settings.isActive {
                Slider(
                    value: Binding(
                        get: { settings.level },
                        set: { newValue in state.update(layer) { $0.level = newValue } }
                    ),
                    in: 0.02...1
                )
                .controlSize(.mini)
                .padding(.leading, 28)
            }
        }
        .animation(.easeOut(duration: 0.18), value: settings.isActive)
    }
}

// MARK: - Small components

private struct IconToggle: View {
    let on: Bool
    let enabled: Bool
    let onSymbol: String
    let offSymbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? onSymbol : offSymbol)
                .font(.system(size: 11))
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .help(help)
    }
}

private struct PresetChip: View {
    let preset: Preset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 15, weight: .light))
                Text(preset.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
        .help(preset.blurb)
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

private struct LabeledSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11))
                .frame(width: 60, alignment: .leading)
            Slider(value: $value, in: 0.15...1)
                .controlSize(.small)
        }
    }
}
