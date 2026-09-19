import AppKit
import SwiftUI

/// Owns Softfall's one real window.
///
/// Deliberately not an `NSWindowController` subclass: that class exists to load
/// a window from a nib, and there is no nib here. All it would add is a storage
/// box we already have.
final class MainWindowController {

    private let window: NSWindow

    init(state: MixState, preview: ScenePreview, onOpenSettings: @escaping () -> Void) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Softfall"
        // The weather runs under the title bar: no title, no bar, just the
        // traffic lights sitting on the sky.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.10, alpha: 1)
        // A programmatically created window releases itself when closed, which
        // would leave this holding a dead object the second time you open it.
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: MainWindowView(state: state, preview: preview, onOpenSettings: onOpenSettings)
        )
        window.contentMinSize = NSSize(width: 320, height: 520)
        window.center()
        // Remembers where you put it, per user, with no code of ours.
        //
        // The name is versioned because the autosaved frame outlives the code:
        // anyone who ran an earlier window would have that frame restored over
        // this one and conclude nothing had changed.
        window.setFrameAutosaveName("SoftfallMainWindow3")
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Clicking the menu bar icon toggles: raise it if it is behind something
    /// or closed, put it away if you are already looking at it.
    func toggle() {
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            show()
        }
    }
}
