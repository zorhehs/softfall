import AppKit

// Built as a plain SwiftPM executable rather than an Xcode project, so the
// application object is set up by hand. `.accessory` keeps Softfall out of the
// Dock and out of the app switcher — it is a menu bar app and nothing else.
let application = NSApplication.shared
let controller = AppDelegate()
application.delegate = controller
application.setActivationPolicy(.accessory)
application.run()
