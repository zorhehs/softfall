import AppKit

/// Builds the menu bar at the top of the screen.
///
/// An app launched from a Swift package has no nib, and therefore no main menu
/// unless one is made by hand. While Softfall was an accessory app that did not
/// matter — an accessory app never owns the menu bar. A regular app does, and
/// without this there would be no About box, no Hide, and no Command-Q.
final class AppMenuController: NSObject, NSMenuDelegate {

    private let state: MixState
    private let updater: Updater
    private let onShowWindow: () -> Void
    private let onShowSettings: () -> Void
    private var sceneMenu: NSMenu?

    init(state: MixState,
         updater: Updater,
         onShowWindow: @escaping () -> Void,
         onShowSettings: @escaping () -> Void) {
        self.state = state
        self.updater = updater
        self.onShowWindow = onShowWindow
        self.onShowSettings = onShowSettings
        super.init()
    }

    func install() {
        let main = NSMenu()
        main.addItem(appMenuItem())
        main.addItem(sceneMenuItem())
        main.addItem(editMenuItem())
        main.addItem(windowMenuItem(of: main))
        NSApp.mainMenu = main
    }

    // MARK: Menus

    private func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Softfall")

        menu.addItem(withTitle: "About Softfall",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        // Where every Mac app keeps it: under About, above Settings. Sparkle
        // greys it out itself while a check is running. A dev copy has no
        // feed to check, so it gets no item rather than a dead one.
        if updater.isAvailable {
            menu.addItem(withTitle: "Check for Updates…",
                         action: #selector(Updater.checkForUpdates(_:)),
                         keyEquivalent: "").target = updater
        }
        menu.addItem(.separator())

        // Command-comma. Every Mac user already knows where settings are; the
        // job is to not be the app that disappoints them.
        menu.addItem(withTitle: "Settings…",
                     action: #selector(showSettings),
                     keyEquivalent: ",").target = self
        menu.addItem(.separator())

        let hide = menu.addItem(withTitle: "Hide Softfall",
                                action: #selector(NSApplication.hide(_:)),
                                keyEquivalent: "h")
        hide.target = NSApp

        let hideOthers = menu.addItem(withTitle: "Hide Others",
                                      action: #selector(NSApplication.hideOtherApplications(_:)),
                                      keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp

        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "").target = NSApp

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Softfall",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q").target = NSApp

        item.submenu = menu
        return item
    }

    private func sceneMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Scene")
        menu.delegate = self
        menu.autoenablesItems = false

        let toggle = menu.addItem(withTitle: "Pause",
                                  action: #selector(togglePlaying),
                                  keyEquivalent: "p")
        toggle.target = self
        toggle.tag = Tag.playPause

        menu.addItem(.separator())

        // Command-1, -2, -3. Three scenes is few enough that every one of them
        // can have a shortcut.
        for (index, scene) in Scene.allCases.enumerated() {
            let sceneItem = menu.addItem(withTitle: scene.title,
                                         action: #selector(chooseScene(_:)),
                                         keyEquivalent: String(index + 1))
            sceneItem.target = self
            sceneItem.representedObject = scene.rawValue
        }

        sceneMenu = menu
        item.submenu = menu
        return item
    }

    /// Nothing in Softfall takes typed input today, but a window that cannot
    /// copy from its own About box feels broken, and this costs eight lines.
    private func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        item.submenu = menu
        return item
    }

    private func windowMenuItem(of main: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")

        let show = menu.addItem(withTitle: "Softfall Window",
                                action: #selector(showWindow),
                                keyEquivalent: "0")
        show.target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom",
                     action: #selector(NSWindow.performZoom(_:)),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Close",
                     action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front",
                     action: #selector(NSApplication.arrangeInFront(_:)),
                     keyEquivalent: "")

        item.submenu = menu
        // Handing the menu to AppKit is what makes open windows list themselves
        // underneath, and what keeps the checkmark on the front one honest.
        NSApp.windowsMenu = menu
        return item
    }

    // MARK: Live state

    private enum Tag {
        static let playPause = 1001
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === sceneMenu else { return }
        menu.item(withTag: Tag.playPause)?.title = state.isPlaying ? "Pause" : "Play"
        for item in menu.items {
            guard let raw = item.representedObject as? String else { continue }
            item.state = state.scene.rawValue == raw ? .on : .off
        }
    }

    // MARK: Actions

    @objc private func togglePlaying() {
        state.isPlaying.toggle()
    }

    @objc private func chooseScene(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let scene = Scene(rawValue: id) else { return }
        state.select(scene)
    }

    @objc private func showWindow() {
        onShowWindow()
    }

    @objc private func showSettings() {
        onShowSettings()
    }
}
