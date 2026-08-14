import AppKit
import Domain
import Foundation
import IOKit.ps

/// `PowerStateProvider` backed by AppKit sleep/wake notifications, lock-screen
/// distributed notifications, Low Power Mode, and IOKit power sources.
///
/// - Display/system sleep is tracked via `NSWorkspace` notifications; the most
///   important one for #204 is `screensDidSleep`, which fires when the display
///   idles off while the machine keeps running — exactly when the old loop kept
///   spawning `claude /usage` and heating the CPU.
/// - Screen lock (`com.apple.screenIsLocked` / `Unlocked`) and Low Power Mode
///   pause the same non-essential refresh path.
/// - Battery state is read on demand from IOKit's power sources (no AC/battery
///   notification exists, and the read is cheap), so the monitor polls it once
///   per tick.
///
/// Thread-safe (`@unchecked Sendable`): the asleep flag and the set of event
/// continuations are guarded by a lock, and IOKit reads are stateless.
public final class SystemPowerStateProvider: PowerStateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var displayAsleep = false
    private var screenLocked = false
    private var lowPowerMode: Bool
    private var continuations: [UUID: AsyncStream<PowerEvent>.Continuation] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var processObservers: [NSObjectProtocol] = []

    public init() {
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.handleDisplay(asleep: true)
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.handleDisplay(asleep: false)
            })
        }

        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleLock(true)
        })
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleLock(false)
        })

        processObservers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo,
            queue: nil
        ) { [weak self] _ in
            self?.handleLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled)
        })
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        let distributed = DistributedNotificationCenter.default()
        for observer in distributedObservers { distributed.removeObserver(observer) }
        for observer in processObservers { NotificationCenter.default.removeObserver(observer) }
        lock.lock()
        let pending = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in pending { continuation.finish() }
    }

    public var isDisplayAsleep: Bool {
        lock.lock(); defer { lock.unlock() }
        return displayAsleep
    }

    public var isScreenLocked: Bool {
        lock.lock(); defer { lock.unlock() }
        return screenLocked
    }

    public var isLowPowerMode: Bool {
        lock.lock(); defer { lock.unlock() }
        return lowPowerMode
    }

    public var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return false
        }
        return (sourceType as String) == kIOPSBatteryPowerValue
    }

    /// Sleep, lock, and Low Power Mode pause background refresh. Manual refresh
    /// remains allowed so a user click is never swallowed.
    public func refreshPausePolicy() -> RefreshPausePolicy {
        .forSystemConditions(
            displayAsleep: isDisplayAsleep,
            screenLocked: isScreenLocked,
            lowPowerMode: isLowPowerMode
        )
    }

    public func events() -> AsyncStream<PowerEvent> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    /// Updates flags before emitting so a consumer re-checking after an event
    /// sees the new pause policy (sleep, lock, or Low Power Mode).
    private func handleDisplay(asleep: Bool) {
        emit(displayAsleep: asleep, screenLocked: nil, lowPowerMode: nil)
    }

    private func handleLock(_ locked: Bool) {
        emit(displayAsleep: nil, screenLocked: locked, lowPowerMode: nil)
    }

    private func handleLowPower(_ enabled: Bool) {
        emit(displayAsleep: nil, screenLocked: nil, lowPowerMode: enabled)
    }

    private func emit(displayAsleep: Bool?, screenLocked: Bool?, lowPowerMode: Bool?) {
        lock.lock()
        if let displayAsleep { self.displayAsleep = displayAsleep }
        if let screenLocked { self.screenLocked = screenLocked }
        if let lowPowerMode { self.lowPowerMode = lowPowerMode }
        let paused = self.displayAsleep || self.screenLocked || self.lowPowerMode
        let listeners = Array(continuations.values)
        lock.unlock()
        for continuation in listeners {
            continuation.yield(paused ? .willSleep : .didWake)
        }
    }
}
