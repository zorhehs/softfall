import AppKit

/// A borderless, transparent, click-through window pinned to one display.
///
/// `ignoresMouseEvents` is what makes the whole idea workable: the weather is
/// painted over your desktop but every click, scroll and gesture lands on
/// whatever is underneath, so nothing about how you use your Mac changes.
final class OverlayWindow: NSWindow {

    init(screen: NSScreen) {
        // The variant taking `screen:` is a convenience initializer, and a
        // subclass has to go through a designated one. Passing the screen's
        // frame as the content rect places the window on that display anyway,
        // because screen frames are already in global coordinates.
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        // Never steal focus, never appear in Exposé, never take a screenshot's
        // attention. It is scenery, not a window.
        animationBehavior = .none
        sharingType = .none
        // Everything drawn here is specified in sRGB, so back the window in
        // sRGB too. Left at the display's own profile — Display P3 on any
        // recent Mac — each layer is redrawn in 16 bits per channel and every
        // one of the rain's sprite blits is pushed through colour management
        // on the CPU. The compositor converts the finished frame to the panel
        // on the GPU, which costs nothing and looks the same.
        colorSpace = .sRGB

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    /// - Parameter showOverFullScreenApps: when false, the window simply is not
    ///   part of full-screen spaces, so anything you open full screen — a film,
    ///   a presentation, an editor — is left completely alone. That is cheaper
    ///   and more reliable than trying to detect full-screen windows.
    func configure(placement: OverlayPlacement, showOverFullScreenApps: Bool) {
        switch placement {
        case .aboveWindows:
            // Deliberately `.floating` rather than the higher overlay level:
            // this sits above your app windows but still below the menu bar,
            // the Dock, and any open menu. Weather should never land on top of
            // a menu you are reading.
            level = .floating
        case .behindWindows:
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        }

        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if showOverFullScreenApps {
            behavior.insert(.fullScreenAuxiliary)
        }
        collectionBehavior = behavior
    }
}
