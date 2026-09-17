import AppKit

// Built as a plain SwiftPM executable rather than an Xcode project, so the
// application object is set up by hand.
//
// `.regular` rather than `.accessory`: Softfall has a Dock icon, a window and
// its own menu bar. The menu bar item is still there, but it is now a shortcut
// into the app rather than the whole of it. Note that the policy set here has
// to agree with the bundle — `LSUIElement` must NOT be in Info.plist, or the
// app starts as an accessory and acquires its Dock icon late and awkwardly.
let application = NSApplication.shared
let controller = AppDelegate()
application.delegate = controller
application.setActivationPolicy(.regular)
application.run()
