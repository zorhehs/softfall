import AppKit
import SwiftUI

/// Owns the Settings window.
///
/// A near-copy of `MainWindowController` on purpose: two small, obvious window
/// owners are easier to follow than one generic one with a mode flag. The
/// differences are the ones that matter — this window is not resizable,
/// because its content is a fixed-size tab view, and it does not restore its
/// frame, because a settings window should open where you last left it only
/// in the sense of "centred".
final class SettingsWindowController {

    private let window: NSWindow

    init(state: MixState, updater: Updater) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Softfall Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(state: state, updater: updater))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
