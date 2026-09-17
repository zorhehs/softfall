import AppKit
import SwiftUI

/// The app lives entirely in the menu bar — no Dock icon, no window in your
/// way. Clicking the icon opens the panel; clicking anywhere else closes it.
final class MenuBarController: NSObject, NSPopoverDelegate {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let state: MixState
    private var eventMonitor: Any?

    init(state: MixState, onQuit: @escaping () -> Void) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let panel = ControlPanelView(state: state, onQuit: onQuit)
        popover.contentViewController = NSHostingController(rootView: panel)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Softfall"
        }

        updateIcon()
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
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
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showContextMenu() {
        let menu = NSMenu()

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

    @objc private func togglePlaying() {
        state.isPlaying.toggle()
    }

    @objc private func chooseScene(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let scene = Scene(rawValue: id) else { return }
        state.select(scene)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func closePanel() {
        if popover.isShown { popover.performClose(nil) }
    }
}
