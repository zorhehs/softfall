import SwiftUI

/// The main window: the weather, edge to edge, with the four things you
/// actually touch laid over it.
///
/// The picture is the same renderer that paints the desktop, so the window is
/// not a control panel *about* the weather — it is a piece of it. Everything
/// drawn over the top is kept thin and white so the scene stays the subject:
/// three words to choose a scene, one italic word to name it, a ring for
/// play/pause, two hairlines for amount and volume.
struct MainWindowView: View {
    @ObservedObject var state: MixState
    let preview: ScenePreview
    var onOpenSettings: () -> Void

    /// The window is a picture until you reach for it. Three seconds after
    /// the pointer stops moving — one after it leaves — the controls sink to
    /// a third and the scene name goes; a twitch of the mouse brings them
    /// back. A window you are not looking at (not key) is idle regardless.
    @State private var idle = false
    @State private var idleTask: Task<Void, Never>?
    @State private var dragging = false
    @Environment(\.controlActiveState) private var activeState

    private var faded: Bool {
        (idle && !dragging) || activeState == .inactive
    }

    var body: some View {
        ZStack {
            Sky(scene: state.scene)
            ScenePreviewRepresentable(preview: preview)
            scrim
                .opacity(faded ? 0.5 : 1)
            // The fire's glow is part of the scene, not the sky, and it rises
            // from the bottom edge — exactly where the scrim is darkest. So it
            // goes over the scrim, at the strength that reads through the text.
            FireGlow(visible: state.scene == .campfire)
            controls
        }
        .frame(minWidth: 320, minHeight: 520)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: faded ? 0.6 : 0.15), value: faded)
        .onAppear { scheduleIdle(after: 3) }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active:
                idle = false
                scheduleIdle(after: 3)
            case .ended:
                scheduleIdle(after: 1)
            }
        }
        .onChange(of: dragging) { _, isDragging in
            if !isDragging { scheduleIdle(after: 3) }
        }
    }

    private func scheduleIdle(after seconds: Double) {
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            idle = true
        }
    }

    // MARK: Layers

    /// Darkens the lower half so white type reads over bright rain. Starts
    /// clear a little above the title and settles near-black at the bottom.
    private var scrim: some View {
        VStack(spacing: 0) {
            Color.clear
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.02, green: 0.03, blue: 0.055).opacity(0), location: 0),
                    .init(color: Color(red: 0.02, green: 0.03, blue: 0.055).opacity(0.6), location: 0.45),
                    .init(color: Color(red: 0.02, green: 0.03, blue: 0.055).opacity(0.8), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 260)
        }
        .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            sceneTabs
                // Leaves room for the traffic lights, which sit over the scene.
                .padding(.top, 36)
                .frame(maxWidth: .infinity)
                .opacity(faded ? 0.3 : 1)

            Spacer(minLength: 0)

            nowPlaying

            VStack(spacing: 14) {
                HairlineSlider(
                    label: "Amount",
                    value: Binding(
                        get: { state.current.level },
                        set: { v in state.updateCurrent { $0.level = v } }
                    ),
                    in: 0.02...1,
                    dragging: $dragging
                )
                HairlineSlider(label: "Volume", value: $state.masterVolume, in: 0...1, dragging: $dragging)
            }
            .padding(.top, 22)
            .opacity(faded ? 0.3 : 1)

            footer
                .padding(.top, 22)
                .opacity(faded ? 0.3 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .foregroundStyle(.white)
    }

    // MARK: Pieces

    private var sceneTabs: some View {
        HStack(spacing: 22) {
            ForEach(Scene.allCases) { scene in
                let selected = scene == state.scene
                Button {
                    state.select(scene)
                } label: {
                    Text(scene.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .frame(height: 1.5)
                                .foregroundStyle(selected ? .white : .clear)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nowPlaying: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.scene.title)
                    .font(.system(size: 46, weight: .light, design: .serif))
                    .italic()
                    .lineLimit(1)
                Text(statusLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            // The name goes entirely when idle; the ring stays faint, so it
            // is still there to click and still there for VoiceOver.
            .opacity(faded ? 0 : 1)

            Spacer(minLength: 0)

            Button {
                state.isPlaying.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.08))
                    Circle()
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .medium))
                        .offset(x: state.isPlaying ? 0 : 1.5)
                }
                .frame(width: 46, height: 46)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(state.isPlaying ? "Pause" : "Resume")
            .padding(.bottom, 4)
            .opacity(faded ? 0.3 : 1)
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
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            Button("Settings…", action: onOpenSettings)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
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

/// What the weather falls in front of. The overlay has the desktop behind it;
/// the window needs a sky of its own, and each scene gets the one it belongs
/// to — overcast blue-grey for rain, near-black for a storm, a warm dark for
/// a fire, with a glow rising from the bottom edge where the embers start.
private struct Sky: View {
    let scene: Scene

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .animation(.easeInOut(duration: 0.7), value: scene)
            .ignoresSafeArea()
    }

    private var colors: [Color] {
        switch scene {
        case .rain:     return [Color(red: 0.16, green: 0.21, blue: 0.27), Color(red: 0.05, green: 0.07, blue: 0.10)]
        case .thunder:  return [Color(red: 0.09, green: 0.10, blue: 0.15), Color(red: 0.03, green: 0.03, blue: 0.05)]
        case .campfire: return [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.10, green: 0.07, blue: 0.05)]
        }
    }
}

/// A warm bloom from the bottom edge, where the embers start.
private struct FireGlow: View {
    let visible: Bool

    var body: some View {
        RadialGradient(
            colors: [
                Color(red: 1.0, green: 0.58, blue: 0.22).opacity(0.5),
                Color(red: 1.0, green: 0.45, blue: 0.15).opacity(0.18),
                .clear
            ],
            center: UnitPoint(x: 0.5, y: 1.08),
            startRadius: 0, endRadius: 360
        )
        .blendMode(.screen)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.7), value: visible)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// A slider drawn as a hairline: a 2-point track, a white fill, a small round
/// thumb. The system slider is right for a form; over a picture it is
/// furniture. Keyboard and VoiceOver still get a proper adjustable control.
private struct HairlineSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Raised while the thumb is held, so the window never fades mid-drag.
    @Binding var dragging: Bool

    init(label: String, value: Binding<Double>, in range: ClosedRange<Double>, dragging: Binding<Bool>) {
        self.label = label
        self._value = value
        self.range = range
        self._dragging = dragging
    }

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))

            GeometryReader { geo in
                let width = geo.size.width
                let x = max(7, min(width - 7, fraction * width))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(height: 2)
                    Capsule()
                        .fill(.white)
                        .frame(width: x, height: 2)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .offset(x: x - 7)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            dragging = true
                            let f = max(0, min(1, drag.location.x / width))
                            value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(height: 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(fraction * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}
