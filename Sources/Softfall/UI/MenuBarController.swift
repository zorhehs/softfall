import AppKit

/// The menu bar icon, which survives the move to a windowed app.
///
/// It is no longer where the controls live — that is the window's job now — so
/// it has shed its popover and kept the two things a status item is genuinely
/// better at than a window: telling you at a glance whether anything is
/// playing, and letting you change scene without raising anything.
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private let state: MixState
    private let onOpenWindow: () -> Void
    private let onQuit: () -> Void

    init(state: MixState, onOpenWindow: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.state = state
        self.onOpenWindow = onOpenWindow
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Softfall"
        }

        updateIcon()
    }

    /// Keeps the menu bar glyph honest about whether anything is playing.
    func updateIcon() {
        guard let button = statusItem.button else { return }
        let name = state.isPlaying && state.current.isActive ? state.scene.symbol : "cloud"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Softfall")
        image?.isTemplate = true
        button.image = image
        button.alphaValue = state.isPlaying ? 1.0 : 0.55
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            onOpenWindow()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Softfall", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: state.isPlaying ? "Pause" : "Play",
            action: #selector(togglePlaying),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        for scene in Scene.allCases {
            let item = NSMenuItem(title: scene.title, action: #selector(chooseScene(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scene.rawValue
            item.state = state.scene == scene ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Softfall", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attaching, popping and detaching is the supported way to show a menu
        // from a status item that also handles plain clicks.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openWindow() {
        onOpenWindow()
    }

    @objc private func togglePlaying() {
        state.isPlaying.toggle()
    }

    @objc private func chooseScene(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let scene = Scene(rawValue: id) else { return }
        state.select(scene)
    }

    @objc private func quit() {
        onQuit()
    }
}
