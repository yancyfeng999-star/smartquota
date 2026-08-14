import Testing
import Foundation
import Observation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Performance protection and refresh lifecycle
///
/// Background refresh is owned by RefreshCoordinator. Sleep / lock / Low Power
/// Mode pause non-essential work. Wake runs one coalesced refresh. Timeouts,
/// cancel, and bounded retry never loop forever. Historical snapshot display
/// does not network. Metrics omit secrets.
///
/// 30-minute residency, 20 extension providers, and reconnect are simulated
/// with a controllable clock — no real half-hour wait.
@Suite("Feature: Performance")
@MainActor
struct PerformanceSpec {

    @Test
    func `sleep pauses background refresh and wake runs one coalesced tick`() async {
        let power = SpecPowerState()
        let clock = SpecGateClock()
        let started = SpecStartGate()
        let probe = SpecProbe(
            providerId: "claude",
            script: [.value(10), .value(20), .value(30)],
            onStart: { await started.mark() }
        )
        let provider = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: SpecImmediateClock()
        )
        var policy = RefreshExecutionPolicy.background
        policy.requestTimeout = nil
        let coordinator = RefreshCoordinator(
            monitor: monitor,
            powerState: power,
            clock: clock,
            backgroundPolicy: policy
        )

        power.setPaused(true)
        coordinator.applyPowerEvent(.willSleep)
        coordinator.setBackgroundRefresh(enabled: true, interval: .seconds(300), providerIds: ["claude"])
        #expect(await probe.starts() == 0)

        power.setPaused(false)
        coordinator.applyPowerEvent(.didWake)
        coordinator.applyPowerEvent(.didWake)
        await started.wait(until: 1)
        await coordinator.waitUntilBackgroundTickCount(1)
        #expect(await probe.starts() == 1)

        coordinator.stopBackgroundRefresh()
        #expect(coordinator.isBackgroundRefreshRunning == false)
        #expect(coordinator.performance.snapshot.inFlightCount == 0)
    }

    @Test
    func `thirty simulated minutes leave no leaked tasks`() async {
        let clock = SpecGateClock()
        let probe = SpecProbe(providerId: "claude", script: [])
        let provider = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: SpecImmediateClock()
        )
        var policy = RefreshExecutionPolicy.background
        policy.requestTimeout = nil
        policy.mergeWindow = nil
        let coordinator = RefreshCoordinator(monitor: monitor, clock: clock, backgroundPolicy: policy)
        coordinator.setBackgroundRefresh(enabled: true, interval: .seconds(300), providerIds: ["claude"])
        await coordinator.waitUntilBackgroundTickCount(1)

        for step in 1...6 {
            await clock.waitUntilSleepCount(step)
            clock.releaseOne()
            await coordinator.waitUntilBackgroundTickCount(step + 1)
        }

        #expect(await probe.starts() == 7)
        coordinator.stopBackgroundRefresh()
        #expect(coordinator.performance.snapshot.inFlightCount == 0)
        #expect(coordinator.isBackgroundRefreshRunning == false)
    }

    @Test
    func `network disconnect retries with backoff then recovers on the next tick`() async {
        let clock = SpecGateClock()
        let probe = SpecProbe(
            providerId: "claude",
            script: [
                .failure(ProbeError.timeout),
                .failure(ProbeError.timeout),
                .failure(ProbeError.timeout),
                .value(64)
            ]
        )
        let provider = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: SpecImmediateClock()
        )
        var policy = RefreshExecutionPolicy.background
        policy.requestTimeout = nil
        let coordinator = RefreshCoordinator(
            monitor: monitor,
            clock: clock,
            backgroundPolicy: policy,
            interactivePolicy: policy
        )

        coordinator.setBackgroundRefresh(enabled: true, interval: .seconds(300), providerIds: ["claude"])
        await clock.waitUntilSleepCount(1)
        clock.releaseOne()
        await clock.waitUntilSleepCount(2)
        clock.releaseOne()
        await coordinator.waitUntilBackgroundTickCount(1)
        #expect(await probe.starts() == 3)
        #expect((provider.lastError as? ProbeError) == .timeout)
        #expect(coordinator.performance.snapshot.connectionFailedCount >= 1)

        await clock.waitUntilSleepCount(3)
        clock.releaseOne()
        await coordinator.waitUntilBackgroundTickCount(2)
        #expect(provider.snapshot?.quotas.first?.percentRemaining == 64)
        #expect(await probe.starts() == 4)

        coordinator.stopBackgroundRefresh()
    }

    @Test
    func `twenty extension providers only refresh enabled memberships and cancel releases work`() async {
        var probes: [SpecProbe] = []
        var providers: [any AIProvider] = []
        let hold = SpecReleaseGate()
        let started = SpecStartGate()
        for index in 0..<20 {
            let probe: SpecProbe
            if index < 3 {
                probe = SpecProbe(
                    providerId: "ext-\(index)",
                    script: [.wait(hold, then: .value(Double(index)))],
                    onStart: { await started.mark() }
                )
            } else {
                probe = SpecProbe(providerId: "ext-\(index)", script: [.value(Double(index))])
            }
            probes.append(probe)
            providers.append(SpecProvider(id: "ext-\(index)", probe: probe, enabled: index < 3))
        }
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: providers),
            clock: SpecImmediateClock()
        )
        let coordinator = RefreshCoordinator(monitor: monitor, maxConcurrent: 2)

        let run = Task { await coordinator.refresh(.allEnabledProviders) }
        await started.wait(until: 2)
        await coordinator.cancel()
        await hold.release()
        await run.value

        #expect(await coordinator.state == .cancelled(completedCount: 2))
        #expect(await probes[0].starts() == 1)
        #expect(await probes[1].starts() == 1)
        #expect(await probes[2].starts() == 0)
        for index in 3..<20 {
            #expect(await probes[index].starts() == 0)
        }
        #expect(coordinator.performance.snapshot.cancelCount >= 1)
        #expect(coordinator.performance.snapshot.inFlightCount == 0)
        #expect(!coordinator.performance.snapshot.logLine.contains("token"))
        #expect(!coordinator.performance.snapshot.logLine.contains("cookie"))
    }

    @Test
    func `historical snapshot display does not trigger a network probe`() async {
        let probe = SpecProbe(providerId: "codex", script: [.value(42)])
        let provider = CodexProvider(probe: probe, settingsRepository: Self.makeSettings())
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: SpecImmediateClock()
        )
        let accounts = ProviderAccountCoordinator(
            providerId: "codex",
            settingsRepository: SpecMultiAccountSettings()
        )
        monitor.registerCoordinator(accounts)
        let coordinator = RefreshCoordinator(monitor: monitor)

        await coordinator.refresh(.provider("codex"))
        let accountId = accounts.activeAccountId
        if let accountId {
            accounts.process(.signOut(accountId: accountId))
        }

        let shown = coordinator.historicalSnapshot(providerId: "codex", accountId: accountId)
        #expect(shown?.quotas.first?.percentRemaining == 42)
        #expect(await probe.starts() == 1)
    }

    // MARK: - Harness

    private static func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }
}

private struct SpecImmediateClock: Clock {
    func sleep(for duration: Duration) async throws {}
    func sleep(nanoseconds: UInt64) async throws {}
}

private final class SpecGateClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            recorded.append(duration)
            let pending = sleepWaiters
            sleepWaiters.removeAll()
            return pending
        }
        ready.forEach { $0.resume() }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.withLock { waiters.append((id, cont)) }
            }
        } onCancel: { [self] in
            let pending = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return nil }
                return waiters.remove(at: index).1
            }
            pending?.resume(throwing: CancellationError())
        }
    }

    func sleep(nanoseconds: UInt64) async throws {
        try await sleep(for: .nanoseconds(Int64(nanoseconds)))
    }

    func waitUntilSleepCount(_ count: Int) async {
        while true {
            if lock.withLock({ recorded.count >= count }) { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let already = lock.withLock { () -> Bool in
                    if recorded.count >= count { return true }
                    sleepWaiters.append(cont)
                    return false
                }
                if already { cont.resume() }
            }
        }
    }

    func releaseOne() {
        let waiter = lock.withLock { waiters.isEmpty ? nil : waiters.removeFirst().1 }
        waiter?.resume()
    }

    func releaseAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            let current = waiters.map(\.1)
            waiters.removeAll()
            return current
        }
        pending.forEach { $0.resume() }
    }
}

private final class SpecPowerState: PowerStateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false

    var isDisplayAsleep: Bool { lock.withLock { paused } }
    var isOnBattery: Bool { false }
    var isScreenLocked: Bool { false }
    var isLowPowerMode: Bool { lock.withLock { paused } }

    func events() -> AsyncStream<PowerEvent> {
        AsyncStream { _ in }
    }

    func setPaused(_ value: Bool) {
        lock.withLock { paused = value }
    }
}

private actor SpecStartGate {
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func mark() {
        count += 1
        let ready = waiters
        waiters.removeAll()
        ready.forEach { $0.resume() }
    }

    func wait(until target: Int) async {
        while count < target {
            await withCheckedContinuation { waiters.append($0) }
        }
    }
}

private actor SpecReleaseGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        let ready = waiters
        waiters.removeAll()
        ready.forEach { $0.resume() }
    }
}

private final class SpecProbe: UsageProbe, @unchecked Sendable {
    enum Step {
        case value(Double)
        case failure(Error)
        case wait(SpecReleaseGate, then: Outcome)
    }

    enum Outcome {
        case value(Double)
        case failure(Error)
    }

    let providerId: String
    private let lock = NSLock()
    private var script: [Step]
    private var startCount = 0
    private let onStart: (@Sendable () async -> Void)?

    init(providerId: String, script: [Step], onStart: (@Sendable () async -> Void)? = nil) {
        self.providerId = providerId
        self.script = script
        self.onStart = onStart
    }

    func starts() async -> Int { lock.withLock { startCount } }

    func probe() async throws -> UsageSnapshot {
        let step = lock.withLock { () -> Step in
            startCount += 1
            return script.isEmpty ? .value(0) : script.removeFirst()
        }
        if let onStart { await onStart() }
        return try await resolve(step)
    }

    func isAvailable() async -> Bool { true }

    private func resolve(_ step: Step) async throws -> UsageSnapshot {
        switch step {
        case let .value(percent):
            return UsageSnapshot(
                providerId: providerId,
                quotas: [UsageQuota(percentRemaining: percent, quotaType: .session, providerId: providerId)],
                capturedAt: Date()
            )
        case let .failure(error):
            throw error
        case let .wait(gate, next):
            await gate.wait()
            switch next {
            case let .value(percent):
                return try await resolve(.value(percent))
            case let .failure(error):
                return try await resolve(.failure(error))
            }
        }
    }
}

@MainActor
@Observable
private final class SpecProvider: AIProvider {
    let id: String
    let name: String
    let cliCommand = ""
    var dashboardURL: URL? { nil }
    var isEnabled: Bool
    private(set) var isSyncing = false
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastError: Error?
    private let probe: any UsageProbe

    init(id: String, probe: any UsageProbe, enabled: Bool) {
        self.id = id
        self.name = id
        self.probe = probe
        self.isEnabled = enabled
    }

    func isAvailable() async -> Bool { await probe.isAvailable() }

    func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let next = try await probe.probe()
            snapshot = next
            lastError = nil
            return next
        } catch {
            lastError = error
            throw error
        }
    }
}

private final class SpecMultiAccountSettings: ProviderSettingsRepository, MultiAccountSettingsRepository, @unchecked Sendable {
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { true }
    func isEnabled(forProvider id: String) -> Bool { true }
    func setEnabled(_ enabled: Bool, forProvider id: String) {}
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
    func accounts(forProvider id: String) -> [ProviderAccountConfig] { [] }
    func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {}
    func removeAccount(accountId: String, forProvider id: String) {}
    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {}
    func activeAccountId(forProvider id: String) -> String? { nil }
    func setActiveAccountId(_ accountId: String?, forProvider id: String) {}
}
