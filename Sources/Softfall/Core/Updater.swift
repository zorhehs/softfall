import AppKit
import Combine
import Sparkle

/// In-app updates, the way every other independently distributed Mac app does
/// them: a quiet check on launch and once a day after that, a sheet when a
/// newer release exists, and a "Check for Updates…" item for the impatient.
///
/// Sparkle does the actual work. This wraps it so the rest of the app talks
/// to one small object, the settings pane can bind to its switches, and the
/// menu item can grey itself out while a check is already running.
///
/// The feed it reads is an `appcast.xml` attached to every GitHub release —
/// `Scripts/build-app.sh` bakes the URL and the public key into Info.plist,
/// and the release workflow signs each archive and writes the feed. A build
/// without those keys (a dev copy, a CI smoke build) has nothing to check
/// against, and Sparkle simply stays idle; `isAvailable` is false and the UI
/// that offers updates is hidden.
final class Updater: NSObject, ObservableObject {

    /// Whether this build can update itself at all. False for a dev copy, and
    /// false for a release whose keys Sparkle would not accept — that is
    /// logged rather than shown, because the person seeing it could do
    /// nothing about it.
    private(set) var isAvailable: Bool

    /// Mirrors Sparkle's own setting so a SwiftUI toggle can bind to it.
    @Published var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    /// True while a check the user asked for is in flight — the menu item and
    /// button disable themselves so a double-click cannot start two.
    @Published private(set) var canCheck = true

    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        isAvailable = !feed.isEmpty && !key.isEmpty

        // The updater is only started when there is a feed to read. Starting
        // it without one makes Sparkle log an error on every launch.
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        checksAutomatically = false
        super.init()

        guard isAvailable else { return }
        do {
            try controller.updater.start()
        } catch {
            NSLog("Softfall: updater not started: \(error.localizedDescription)")
            isAvailable = false
            return
        }
        // Read once Sparkle is up: before that it has not looked at
        // Info.plist, where SUEnableAutomaticChecks turns this on by default.
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    /// The explicit check: shows progress and says so when nothing is newer,
    /// unlike the background one.
    @objc func checkForUpdates(_ sender: Any?) {
        guard isAvailable else { return }
        controller.checkForUpdates(sender)
    }

    /// The version this build is, for the settings pane.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
