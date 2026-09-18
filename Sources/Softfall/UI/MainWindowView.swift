import SwiftUI

/// The main window: the four things you actually touch.
///
/// This window had sixteen controls in it. Placement, opacity, colour, tone,
/// frame rate, display choices, ducking, battery and login behaviour are all
/// things you set once and then forget, and putting them in front of someone
/// every time they want to turn the rain down is how a small app starts
/// feeling like a control panel. They live in Settings now, behind Command-,
/// where the platform has trained everyone to look for them.
///
/// What is left is the instrument: which weather, whether it is running, how
/// much of it, and how loud.
struct MainWindowView: View {
    @ObservedObject var state: MixState
    var onOpenSettings: () -> Void

    /// A segmented picker wants a plain binding; selecting a scene also starts
    /// playback, which `select(_:)` already handles.
    private var scene: Binding<Scene> {
        Binding(get: { state.scene }, set: { state.select($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: scene) {
                ForEach(Scene.allCases) { scene in
                    Text(scene.title).tag(scene)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            transport

            // `.columns` aligns the two labels without the grouped boxes a
            // settings pane wants — the same alignment, none of the furniture.
            Form {
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
            }
            .formStyle(.columns)

            Spacer(minLength: 0)

            footer
        }
        .padding(18)
        .frame(minWidth: 340, minHeight: 300)
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                state.isPlaying.toggle()
            } label: {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(state.isPlaying ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(state.isPlaying ? "Pause" : "Resume")

            VStack(alignment: .leading, spacing: 2) {
                Text(state.scene.title)
                    .font(.headline)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
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

            Spacer()

            Button("Settings…", action: onOpenSettings)
                .buttonStyle(.link)
        }
        .font(.subheadline)
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
}
