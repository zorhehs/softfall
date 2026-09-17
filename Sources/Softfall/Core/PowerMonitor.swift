import Foundation
import AppKit
import IOKit.ps

/// Watches the things that should make an always-on overlay back off by itself:
/// running on battery, Low Power Mode, and the display going to sleep.
///
/// An ambient app that quietly drains a laptop is not relaxing, so this is
/// treated as a feature rather than an optimisation.
final class PowerMonitor: NSObject {

    private(set) var onBattery = false
    private(set) var lowPowerMode = false
    private(set) var displaysAsleep = false
    private(set) var screenLocked = false

    /// True when visuals should be suspended regardless of user settings.
    var shouldSuspendVisuals: Bool {
        displaysAsleep || screenLocked
    }

    var onChange: (() -> Void)?

    private var pollTimer: Timer?

    override init() {
        super.init()

        refreshPowerSource()
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(displaysSlept),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaysWoke),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenDidLock),
                                name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenDidUnlock),
                                name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lowPowerModeChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )

        // Plugging a laptop in posts no notification we can rely on, so the
        // power source itself is polled — cheaply, and rarely.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshPowerSource()
        }
        pollTimer?.tolerance = 10
    }

    deinit {
        pollTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func refreshPowerSource() {
        let previous = onBattery
        var battery = false

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any] else { continue }
                if let state = description[kIOPSPowerSourceStateKey] as? String {
                    if state == kIOPSBatteryPowerValue { battery = true }
                }
            }
        }

        onBattery = battery
        if previous != battery { onChange?() }
    }

    @objc private func lowPowerModeChanged() {
        let previous = lowPowerMode
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if previous != lowPowerMode { onChange?() }
    }

    @objc private func displaysSlept() { displaysAsleep = true; onChange?() }
    @objc private func displaysWoke() { displaysAsleep = false; onChange?() }
    @objc private func screenDidLock() { screenLocked = true; onChange?() }
    @objc private func screenDidUnlock() { screenLocked = false; onChange?() }
}
