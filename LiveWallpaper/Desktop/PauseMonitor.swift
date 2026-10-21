import AppKit
import IOKit.ps

/// Следит за питанием, режимом энергосбережения, сном экрана и блокировкой.
@MainActor
final class PauseMonitor: NSObject {
    var onChange: (() -> Void)?

    private(set) var isOnBattery = false
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var isScreenAsleep = false
    private(set) var isSessionInactive = false
    private(set) var isLocked = false

    private var timer: Timer?

    override init() {
        super.init()
        isOnBattery = Self.readIsOnBattery()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidResign),
                              name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidBecomeActive),
                              name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked),
                                name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked),
                                name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)

        // Источник питания проще опрашивать, чем подписываться на IOKit run loop source.
        let timer = Timer(timeInterval: 10, target: self, selector: #selector(pollPower),
                          userInfo: nil, repeats: true)
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func shouldPause(_ prefs: Preferences) -> Bool {
        if isScreenAsleep || isSessionInactive || isLocked { return true }
        if prefs.pauseOnBattery && isOnBattery { return true }
        if prefs.pauseOnLowPower && isLowPowerMode { return true }
        return false
    }

    private static func readIsOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == "Battery Power" // kIOPSBatteryPowerValue
    }

    private func update(_ change: () -> Void) {
        change()
        onChange?()
    }

    @objc private func screensDidSleep() { update { isScreenAsleep = true } }
    @objc private func screensDidWake() { update { isScreenAsleep = false } }
    @objc private func sessionDidResign() { update { isSessionInactive = true } }
    @objc private func sessionDidBecomeActive() { update { isSessionInactive = false } }
    @objc private func screenLocked() { update { isLocked = true } }
    @objc private func screenUnlocked() { update { isLocked = false } }

    @objc nonisolated private func powerStateChanged() {
        // Уведомление приходит с произвольного потока.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.update { self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
            }
        }
    }

    @objc private func pollPower() {
        let onBattery = Self.readIsOnBattery()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard onBattery != isOnBattery || lowPower != isLowPowerMode else { return }
        update {
            isOnBattery = onBattery
            isLowPowerMode = lowPower
        }
    }
}
