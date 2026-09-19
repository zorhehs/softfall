import AppKit
import SwiftUI

/// The weather, inside the main window.
///
/// This is not a mockup of the overlay: it is a second `SceneLayers`, the same
/// renderer that paints the desktop, built at window size and stepped by its
/// own display link. Whatever the desktop is doing, the window is doing too —
/// same rain, same bolt, same embers — which is what makes the window feel
/// like the app rather than a remote control for it.
final class ScenePreview {

    fileprivate weak var view: ScenePreviewView?
    private weak var state: MixState?

    init(state: MixState) {
        self.state = state
    }

    /// Called whenever the mix changes, alongside the overlay's own refresh.
    func refresh() {
        guard let state, let view else { return }
        view.apply(state)
    }

    /// Fired by the overlay so the window lights up in the same instant.
    func flashLightning(_ strike: LightningStrike) {
        guard let state, state.isPlaying, state.scene == .thunder, state.current.picture else { return }
        view?.scene.flashLightning(strike, opacityScale: 1.0)
    }

    func gust(_ strike: LightningStrike) {
        guard let state, state.isPlaying, state.scene == .thunder, state.current.picture else { return }
        view?.scene.gust(strike)
    }

    fileprivate func attach(_ view: ScenePreviewView) {
        self.view = view
        refresh()
    }
}

/// Hosts the scene layer tree and keeps its display link honest: paused when
/// the weather is paused, paused when the window is closed or covered.
final class ScenePreviewView: NSView {

    let scene = SceneLayers()
    private let link = DisplayLinkDriver()
    private var built: CGSize = .zero
    private weak var lastState: MixState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // The overlay dims itself to the user's chosen visibility, which is
        // about not overwhelming a desktop. The window is *for* the weather,
        // so it gets the full picture.
        scene.opacityOverride = 1.0
        // Ember rate is tuned per display and floors at a sparse setting for
        // small screens. A window is not a small screen — it is close up.
        scene.emberScale = 4
        layer?.addSublayer(scene.root)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size != .zero, let window else { return }
        let scale = window.backingScaleFactor
        if built == .zero {
            scene.build(size: size, scale: scale)
        } else if size != built {
            scene.resize(to: size, scale: scale)
        }
        built = size
        scene.root.frame = CGRect(origin: .zero, size: size)
        if let lastState { apply(lastState) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        guard let window else {
            link.stop()
            return
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        link.onFrame = { [weak self] dt in
            guard let self else { return }
            self.scene.advance(dt: dt)
            if !self.scene.wantsAnimation { self.link.isPaused = true }
        }
        link.start(in: self, rate: lastState?.frameRate ?? .thirty)
        link.isPaused = true
        needsLayout = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        link.stop()
    }

    @objc private func occlusionChanged() {
        if let lastState { apply(lastState) }
    }

    fileprivate func apply(_ state: MixState) {
        lastState = state
        guard built != .zero else { return }

        let onScreen = window?.occlusionState.contains(.visible) ?? false

        // Pausing is handled the way the desktop handles it: the scene is told
        // there is nothing to draw, the drops already falling land, and the
        // layer hides itself. The link keeps ticking until then.
        scene.update(state: state)
        link.setFrameRate(state.powerSaving ? .thirty : state.frameRate)
        link.isPaused = !(onScreen && scene.wantsAnimation)
    }
}

/// SwiftUI side of the preview.
struct ScenePreviewRepresentable: NSViewRepresentable {
    let preview: ScenePreview

    func makeNSView(context: Context) -> ScenePreviewView {
        let view = ScenePreviewView(frame: .zero)
        preview.attach(view)
        return view
    }

    func updateNSView(_ nsView: ScenePreviewView, context: Context) {}
}
