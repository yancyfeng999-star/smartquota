import Testing
import Foundation
import Observation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("RefreshCoordinator Tests")
@MainActor
struct RefreshCoordinatorTests {

    @Test
    func `current membership refresh only probes the selected enabled provider`() async {
        let env = makeEnv()
        given(env.claudeProbe).isAvailable().willReturn(true)
        given(env.codexProbe).isAvailable().willReturn(true)
        given(env.claudeProbe).probe().willReturn(env.snapshot("claude", percent: 40))
        given(env.codexProbe).probe().willReturn(env.snapshot("codex", percent: 80))

        env.monitor.selectedProviderId = "codex"
        let coordinator = RefreshCoordinator(monitor: env.monitor)

        await coordinator.refresh(.provider("codex"))

        #expect(await coordinator.state == .completed(successCount: 1, failureCount: 0))
        #expect(env.codex.snapshot?.quotas.first?.percentRemaining == 80)
        #expect(env.claude.snapshot == nil)
    }

    @Test
    func `refresh all reports success and failure counts and keeps the old snapshot on timeout`() async {
        let captured = Date(timeIntervalSince1970: 100)
        let claude = ControllableProbe(providerId: "claude", script: [.value(percent: 22)])
        let codex = ControllableProbe(
            providerId: "codex",
            script: [.value(percent: 55, capturedAt: captured), .error(ProbeError.timeout)]
        )
        let settings = Self.makeSettings()
        let claudeProvider = ClaudeProvider(probe: claude, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codex, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [claudeProvider, codexProvider]),
            clock: ImmediateClock()
        )
        await monitor.refresh(providerId: "codex")
        #expect(codexProvider.snapshot?.quotas.first?.percentRemaining == 55)

        let coordinator = RefreshCoordinator(monitor: monitor)
        await coordinator.refresh(.allEnabledProviders)

        #expect(await coordinator.state == .completed(successCount: 1, failureCount: 1))
        #expect(coordinator.lastSuccessCount == 1)
        #expect(coordinator.lastFailureCount == 1)
        #expect(claudeProvider.snapshot?.quotas.first?.percentRemaining == 22)
        #expect(codexProvider.snapshot?.quotas.first?.percentRemaining == 55)
        #expect(codexProvider.snapshot?.capturedAt == captured)
        #expect((codexProvider.lastError as? ProbeError) == .timeout)
        #expect(RefreshFailureClassifier.classify(codexProvider.lastError!) == .connectionFailed)
    }

    @Test
    func `three members success timeout and cancel keep snapshots and start no further work`() async {
        let started = ProbeStartGate()
        let holdTimeout = ReleaseGate()
        let claude = ControllableProbe(
            providerId: "claude",
            script: [.value(percent: 10), .value(percent: 90)]
        )
        let codex = ControllableProbe(
            providerId: "codex",
            script: [.value(percent: 20), .wait(holdTimeout, then: .failure(ProbeError.timeout))],
            onStart: { await started.mark("codex") }
        )
        let gemini = ControllableProbe(
            providerId: "gemini",
            script: [.value(percent: 30), .value(percent: 1)],
            onStart: { await started.mark("gemini") }
        )
        let settings = Self.makeSettings()
        let claudeProvider = ClaudeProvider(probe: claude, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codex, settingsRepository: settings)
        let geminiProvider = GeminiProvider(probe: gemini, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [claudeProvider, codexProvider, geminiProvider]),
            clock: ImmediateClock()
        )
        let coordinator = RefreshCoordinator(monitor: monitor, maxConcurrent: 2)

        await coordinator.refresh(.allEnabledProviders)
        #expect(await coordinator.state == .completed(successCount: 3, failureCount: 0))
        #expect(claudeProvider.snapshot?.quotas.first?.percentRemaining == 10)
        #expect(codexProvider.snapshot?.quotas.first?.percentRemaining == 20)
        #expect(geminiProvider.snapshot?.quotas.first?.percentRemaining == 30)

        await started.reset()
        let run = Task { await coordinator.refresh(.allEnabledProviders) }
        await started.wait(untilCount: 1)
        await coordinator.cancel()
        await holdTimeout.release()
        await run.value

        #expect(await coordinator.state == .cancelled(completedCount: 2))
        #expect(coordinator.lastSuccessCount == 1)
        #expect(coordinator.lastFailureCount == 1)
        #expect(claudeProvider.snapshot?.quotas.first?.percentRemaining == 90)
        #expect(codexProvider.snapshot?.quotas.first?.percentRemaining == 20)
        #expect((codexProvider.lastError as? ProbeError) == .timeout)
        #expect(geminiProvider.snapshot?.quotas.first?.percentRemaining == 30)
        #expect(await gemini.startCount() == 1)
        #expect(coordinator.didStartProvider("gemini") == false)
    }

    @Test
    func `overlapping same provider reuses in-flight work and a second all-refresh is rejected`() async {
        let hold = ReleaseGate()
        let started = ProbeStartGate()
        let probe = ControllableProbe(
            providerId: "claude",
            script: [.wait(hold, then: .success(percent: 44))],
            onStart: { await started.mark("claude") }
        )
        let settings = Self.makeSettings()
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock()
        )
        let coordinator = RefreshCoordinator(monitor: monitor)

        let first = Task { await coordinator.refresh(.provider("claude")) }
        await started.wait(untilCount: 1)
        let second = Task { await coordinator.refresh(.provider("claude")) }
        await hold.release()
        await first.value
        await second.value

        #expect(await probe.startCount() == 1)
        #expect(await coordinator.state == .completed(successCount: 1, failureCount: 0))
        #expect(provider.snapshot?.quotas.first?.percentRemaining == 44)

        let holdAll = ReleaseGate()
        let startedAll = ProbeStartGate()
        let claude2 = ControllableProbe(
            providerId: "claude",
            script: [.wait(holdAll, then: .success(percent: 11))],
            onStart: { await startedAll.mark("claude") }
        )
        let codex2 = ControllableProbe(providerId: "codex", script: [.value(percent: 99)])
        let claudeProvider = ClaudeProvider(probe: claude2, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codex2, settingsRepository: settings)
        let multi = QuotaMonitor(
            providers: AIProviders(providers: [claudeProvider, codexProvider]),
            clock: ImmediateClock()
        )
        multi.selectedProviderId = "claude"
        let multiCoordinator = RefreshCoordinator(monitor: multi)
        let running = Task { await multiCoordinator.refresh(.provider("claude")) }
        await startedAll.wait(untilCount: 1)
        await multiCoordinator.refresh(.allEnabledProviders)
        #expect(await multiCoordinator.state.isBusy)
        if case let .running(scope, _) = await multiCoordinator.state {
            #expect(scope == .provider("claude"))
        } else {
            Issue.record("expected running current-member refresh")
        }
        #expect(await codex2.startCount() == 0)
        await holdAll.release()
        await running.value
        #expect(codexProvider.snapshot == nil)
    }

    @Test
    func `sleep pauses background policy and wake does not start a manual refresh`() async {
        let power = ControllablePowerState()
        let settings = Self.makeSettings()
        let probe = ControllableProbe(providerId: "claude", script: [.value(percent: 50)])
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock(),
            powerStateProvider: power
        )
        let coordinator = RefreshCoordinator(monitor: monitor, powerState: power)

        #expect(coordinator.pausePolicy == .active)
        await coordinator.applyPowerEvent(.willSleep)
        #expect(coordinator.pausePolicy == .asleep)
        #expect(coordinator.pausePolicy.allowManualRefresh)

        await coordinator.refresh(.provider("claude"))
        #expect(await coordinator.state == .completed(successCount: 1, failureCount: 0))
        #expect(provider.snapshot?.quotas.first?.percentRemaining == 50)

        await coordinator.applyPowerEvent(.didWake)
        #expect(coordinator.pausePolicy == .active)
        #expect(await coordinator.state == .completed(successCount: 1, failureCount: 0))
        #expect(await probe.startCount() == 1)
    }

    @Test
    func `not logged in is distinct from connection failed and both stay off live quota`() async {
        let claude = ControllableProbe(
            providerId: "claude",
            script: [.value(percent: 12), .error(ProbeError.authenticationRequired)]
        )
        let codex = ControllableProbe(
            providerId: "codex",
            script: [.value(percent: 8), .error(ProbeError.timeout)]
        )
        let settings = Self.makeSettings()
        let claudeProvider = ClaudeProvider(probe: claude, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codex, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [claudeProvider, codexProvider]),
            clock: ImmediateClock()
        )
        await monitor.refreshAll()
        #expect(monitor.overallStatus == .critical)

        let coordinator = RefreshCoordinator(monitor: monitor)
        await coordinator.refresh(.allEnabledProviders)

        #expect(RefreshFailureClassifier.classify(claudeProvider.lastError!) == .notLoggedIn)
        #expect(RefreshFailureClassifier.classify(codexProvider.lastError!) == .connectionFailed)
        #expect(claudeProvider.snapshot?.quotas.first?.percentRemaining == 12)
        #expect(codexProvider.snapshot?.quotas.first?.percentRemaining == 8)
        #expect(monitor.overallStatus == .healthy)
        #expect(monitor.lowestQuota() == nil)
        #expect(monitor.quota(providerId: "codex", quotaKey: "session") == nil)
        #expect(monitor.connectedAccountSnapshot(providerId: "claude") == nil)
    }

    @Test
    func `background loop is owned by the coordinator and stops without leaking tasks`() async {
        let clock = GateClock()
        let probe = ControllableProbe(providerId: "claude", script: [
            .value(percent: 11), .value(percent: 22), .value(percent: 33)
        ])
        let settings = Self.makeSettings()
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock()
        )
        var policy = RefreshExecutionPolicy.background
        policy.requestTimeout = nil
        policy.mergeWindow = nil
        let coordinator = RefreshCoordinator(monitor: monitor, clock: clock, backgroundPolicy: policy)

        coordinator.setBackgroundRefresh(enabled: true, interval: .seconds(300), providerIds: ["claude"])
        await coordinator.waitUntilBackgroundTickCount(1)

        #expect(coordinator.isBackgroundRefreshRunning)
        #expect(await probe.startCount() == 1)
        #expect(provider.snapshot?.quotas.first?.percentRemaining == 11)

        await clock.waitUntilSleepCount(1)
        clock.releaseOne()
        await coordinator.waitUntilBackgroundTickCount(2)
        #expect(await probe.startCount() == 2)

        coordinator.stopBackgroundRefresh()
        #expect(coordinator.isBackgroundRefreshRunning == false)
        #expect(coordinator.performance.snapshot.inFlightCount == 0)
        #expect(clock.durations.contains(.seconds(300)))
    }

    @Test
    func `sleep lock and low power pause background and wake coalesces to one refresh`() async {
        let power = ControllablePowerState()
        let clock = GateClock()
        let started = ProbeStartGate()
        let probe = ControllableProbe(
            providerId: "claude",
            script: [.value(percent: 10), .value(percent: 20), .value(percent: 30)],
            onStart: { await started.mark("claude") }
        )
        let settings = Self.makeSettings()
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock()
        )
        var policy = RefreshExecutionPolicy.background
        policy.requestTimeout = nil
        policy.mergeWindow = nil
        let coordinator = RefreshCoordinator(monitor: monitor, powerState: power, clock: clock, backgroundPolicy: policy)

        power.setLocked(true)
        coordinator.applyPowerEvent(.willSleep)
        #expect(coordinator.pausePolicy.pauseBackgroundRefresh)
        #expect(coordinator.pausePolicy.allowManualRefresh)

        coordinator.setBackgroundRefresh(enabled: true, interval: .seconds(300), providerIds: ["claude"])
        #expect(await probe.startCount() == 0)
        #expect(coordinator.isBackgroundRefreshRunning == false)

        power.setLocked(false)
        coordinator.applyPowerEvent(.didWake)
        coordinator.applyPowerEvent(.didWake)
        coordinator.applyPowerEvent(.didWake)
        await started.wait(untilCount: 1)
        await coordinator.waitUntilBackgroundTickCount(1)
        #expect(await probe.startCount() == 1)

        power.setLowPower(true)
        coordinator.applyPowerEvent(.willSleep)
        let afterLowPower = await probe.startCount()
        #expect(coordinator.pausePolicy.pauseBackgroundRefresh)
        #expect(afterLowPower == 1)

        power.setLowPower(false)
        coordinator.applyPowerEvent(.didWake)
        await started.wait(untilCount: 2)
        await coordinator.waitUntilBackgroundTickCount(2)
        #expect(await probe.startCount() == 2)

        coordinator.stopBackgroundRefresh()
    }

    @Test
    func `connection failures retry with backoff and stop after the attempt cap`() async {
        let clock = GateClock()
        let probe = ControllableProbe(
            providerId: "claude",
            script: [
                .error(ProbeError.timeout),
                .error(ProbeError.timeout),
                .error(ProbeError.timeout),
                .value(percent: 88)
            ]
        )
        let settings = Self.makeSettings()
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock()
        )
        var policy = RefreshExecutionPolicy.background
        policy.requestTimeout = nil
        let coordinator = RefreshCoordinator(
            monitor: monitor,
            clock: clock,
            backgroundPolicy: policy,
            interactivePolicy: policy
        )

        let run = Task { await coordinator.refresh(.provider("claude"), policy: policy) }
        await clock.waitUntilSleepCount(1)
        clock.releaseOne()
        await clock.waitUntilSleepCount(2)
        clock.releaseOne()
        await run.value

        #expect(await probe.startCount() == 3)
        #expect(await coordinator.state == .completed(successCount: 0, failureCount: 1))
        #expect(provider.snapshot == nil)
        #expect((provider.lastError as? ProbeError) == .timeout)
        #expect(clock.durations.filter { $0 == .milliseconds(250) || $0 == .milliseconds(500) }.count == 2)
        #expect(coordinator.performance.snapshot.connectionFailedCount == 1)
        #expect(await probe.startCount() == 3)
    }

    @Test
    func `authentication failure is not retried`() async {
        let clock = GateClock()
        let probe = ControllableProbe(
            providerId: "claude",
            script: [.error(ProbeError.authenticationRequired), .value(percent: 99)]
        )
        let settings = Self.makeSettings()
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock()
        )
        var policy = RefreshExecutionPolicy.background
        policy.requestTimeout = nil
        let coordinator = RefreshCoordinator(monitor: monitor, clock: clock)

        await coordinator.refresh(.provider("claude"), policy: policy)

        #expect(await probe.startCount() == 1)
        #expect(RefreshFailureClassifier.classify(provider.lastError!) == .notLoggedIn)
        #expect(coordinator.performance.snapshot.notLoggedInCount == 1)
        #expect(clock.durations.isEmpty)
    }

    @Test
    func `request timeout counts as a connection failure and increments cancel`() async {
        let hold = ReleaseGate()
        let probe = ControllableProbe(
            providerId: "claude",
            script: [.wait(hold, then: .success(percent: 40))]
        )
        let settings = Self.makeSettings()
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock()
        )
        var policy = RefreshExecutionPolicy.interactive
        policy.requestTimeout = .milliseconds(1)
        let coordinator = RefreshCoordinator(
            monitor: monitor,
            clock: ImmediateClock(),
            interactivePolicy: policy
        )

        let run = Task { await coordinator.refresh(.provider("claude"), policy: policy) }
        await run.value
        await hold.release()

        #expect(await coordinator.state == .completed(successCount: 0, failureCount: 1))
        #expect(coordinator.performance.snapshot.cancelCount >= 1)
        #expect(coordinator.performance.snapshot.connectionFailedCount >= 1)
        #expect(coordinator.performance.snapshot.logLine.contains("duration_ms="))
        #expect(coordinator.performance.snapshot.logLine.contains("cancels="))
        #expect(!coordinator.performance.snapshot.logLine.contains("sk-"))
        #expect(!coordinator.performance.snapshot.logLine.contains("Bearer"))
    }

    @Test
    func `historical snapshot display does not probe the network`() async {
        let probe = ControllableProbe(
            providerId: "codex",
            script: [.value(percent: 42, capturedAt: Date(timeIntervalSince1970: 50))]
        )
        let settings = Self.makeSettings()
        let multi = InMemoryMultiAccountSettings()
        let provider = CodexProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock()
        )
        let accounts = ProviderAccountCoordinator(providerId: "codex", settingsRepository: multi)
        monitor.registerCoordinator(accounts)
        let coordinator = RefreshCoordinator(monitor: monitor)

        await coordinator.refresh(.provider("codex"))
        #expect(await probe.startCount() == 1)
        let accountId = accounts.activeAccountId
        accounts.process(.signOut(accountId: accountId ?? ""))

        let displayed = coordinator.historicalSnapshot(providerId: "codex", accountId: accountId)
        #expect(displayed?.quotas.first?.percentRemaining == 42)
        #expect(await probe.startCount() == 1)
        #expect(monitor.historicalSnapshot(providerId: "codex")?.quotas.first?.percentRemaining == 42)
    }

    @Test
    func `disabled memberships are not refreshed when twenty extension providers are registered`() async {
        let settings = Self.makeSettings()
        var probes: [ControllableProbe] = []
        var providers: [any AIProvider] = []
        for index in 0..<20 {
            let probe = ControllableProbe(providerId: "ext-\(index)", script: [.value(percent: Double(index))])
            probes.append(probe)
            let enabled = index < 3
            providers.append(ConfigurableQuotaProvider(id: "ext-\(index)", probe: probe, enabled: enabled))
        }
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: providers),
            clock: ImmediateClock()
        )
        let coordinator = RefreshCoordinator(monitor: monitor, maxConcurrent: 2)

        await coordinator.refresh(.allEnabledProviders)

        #expect(await coordinator.state == .completed(successCount: 3, failureCount: 0))
        #expect(await probes[0].startCount() == 1)
        #expect(await probes[1].startCount() == 1)
        #expect(await probes[2].startCount() == 1)
        for index in 3..<20 {
            #expect(await probes[index].startCount() == 0)
        }
        #expect(coordinator.performance.snapshot.taskCount == 3)
        #expect(coordinator.performance.snapshot.inFlightCount == 0)
    }

    @Test
    func `thirty simulated minutes of background ticks leave no in-flight work`() async {
        let clock = GateClock()
        let probe = ControllableProbe(providerId: "claude", script: [])
        let settings = Self.makeSettings()
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: ImmediateClock()
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

        #expect(await probe.startCount() == 7)
        coordinator.stopBackgroundRefresh()
        #expect(coordinator.isBackgroundRefreshRunning == false)
        #expect(coordinator.performance.snapshot.inFlightCount == 0)
        #expect(clock.durations.filter { $0 == .seconds(300) }.count >= 6)
    }

    // MARK: - Harness

    private struct ImmediateClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private struct Env {
        let claudeProbe: MockUsageProbe
        let codexProbe: MockUsageProbe
        let geminiProbe: MockUsageProbe
        let claude: ClaudeProvider
        let codex: CodexProvider
        let gemini: GeminiProvider
        let monitor: QuotaMonitor

        func snapshot(_ providerId: String, percent: Double, capturedAt: Date = Date()) -> UsageSnapshot {
            UsageSnapshot(
                providerId: providerId,
                quotas: [UsageQuota(percentRemaining: percent, quotaType: .session, providerId: providerId)],
                capturedAt: capturedAt
            )
        }
    }

    private func makeEnv() -> Env {
        let settings = Self.makeSettings()
        let claudeProbe = MockUsageProbe()
        let codexProbe = MockUsageProbe()
        let geminiProbe = MockUsageProbe()
        given(geminiProbe).isAvailable().willReturn(false)
        let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let gemini = GeminiProvider(probe: geminiProbe, settingsRepository: settings)
        gemini.isEnabled = false
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [claude, codex, gemini]),
            clock: ImmediateClock()
        )
        return Env(
            claudeProbe: claudeProbe,
            codexProbe: codexProbe,
            geminiProbe: geminiProbe,
            claude: claude,
            codex: codex,
            gemini: gemini,
            monitor: monitor
        )
    }

    private static func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }
}

// MARK: - Controllable collaborators

private actor ProbeStartGate {
    private var ids: [String] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func mark(_ id: String) {
        ids.append(id)
        let ready = waiters
        waiters.removeAll()
        ready.forEach { $0.resume() }
    }

    func wait(untilCount count: Int) async {
        while ids.count < count {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func reset() {
        ids.removeAll()
    }
}

private actor ReleaseGate {
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

private final class ControllableProbe: UsageProbe, @unchecked Sendable {
    enum Step {
        case value(percent: Double, capturedAt: Date = Date())
        case error(Error)
        case wait(ReleaseGate, then: Outcome)
    }

    enum Outcome {
        case success(percent: Double)
        case failure(Error)
    }

    let providerId: String
    private let lock = NSLock()
    private var script: [Step]
    private var starts = 0
    private let onStart: (@Sendable () async -> Void)?

    init(providerId: String, script: [Step], onStart: (@Sendable () async -> Void)? = nil) {
        self.providerId = providerId
        self.script = script
        self.onStart = onStart
    }

    func startCount() async -> Int {
        lock.withLock { starts }
    }

    func probe() async throws -> UsageSnapshot {
        let step = lock.withLock { () -> Step in
            starts += 1
            return script.isEmpty ? Step.value(percent: 0) : script.removeFirst()
        }
        if let onStart { await onStart() }
        switch step {
        case let .value(percent, capturedAt):
            return snapshot(percent: percent, capturedAt: capturedAt)
        case let .error(error):
            throw error
        case let .wait(gate, outcome):
            await gate.wait()
            switch outcome {
            case let .success(percent):
                return snapshot(percent: percent)
            case let .failure(error):
                throw error
            }
        }
    }

    func isAvailable() async -> Bool { true }

    private func snapshot(percent: Double, capturedAt: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            providerId: providerId,
            quotas: [UsageQuota(percentRemaining: percent, quotaType: .session, providerId: providerId)],
            capturedAt: capturedAt
        )
    }
}

private final class ControllablePowerState: PowerStateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var asleep = false
    private var locked = false
    private var lowPower = false
    private var continuations: [UUID: AsyncStream<PowerEvent>.Continuation] = [:]

    var isDisplayAsleep: Bool {
        lock.withLock { asleep }
    }

    var isOnBattery: Bool { false }

    var isScreenLocked: Bool {
        lock.withLock { locked }
    }

    var isLowPowerMode: Bool {
        lock.withLock { lowPower }
    }

    func events() -> AsyncStream<PowerEvent> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations[id] = nil
                self?.lock.unlock()
            }
        }
    }

    func setAsleep(_ value: Bool) {
        emit(asleep: value, locked: nil, lowPower: nil)
    }

    func setLocked(_ value: Bool) {
        emit(asleep: nil, locked: value, lowPower: nil)
    }

    func setLowPower(_ value: Bool) {
        emit(asleep: nil, locked: nil, lowPower: value)
    }

    private func emit(asleep: Bool?, locked: Bool?, lowPower: Bool?) {
        lock.lock()
        if let asleep { self.asleep = asleep }
        if let locked { self.locked = locked }
        if let lowPower { self.lowPower = lowPower }
        let paused = self.asleep || self.locked || self.lowPower
        let listeners = Array(continuations.values)
        lock.unlock()
        for continuation in listeners {
            continuation.yield(paused ? .willSleep : .didWake)
        }
    }
}

private final class GateClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []

    var durations: [Duration] {
        lock.withLock { recorded }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let sleepReady = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            recorded.append(duration)
            let pending = sleepWaiters
            sleepWaiters.removeAll()
            return pending
        }
        sleepReady.forEach { $0.resume() }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    waiters.append((id, cont))
                    return false
                }
                if cancelled { cont.resume(throwing: CancellationError()) }
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

@MainActor
@Observable
private final class ConfigurableQuotaProvider: AIProvider {
    let id: String
    let name: String
    let cliCommand = ""
    var dashboardURL: URL? { nil }
    var isEnabled: Bool
    private(set) var isSyncing = false
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastError: Error?
    private let probe: any UsageProbe

    init(id: String, probe: any UsageProbe, enabled: Bool = true) {
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

private final class InMemoryMultiAccountSettings: ProviderSettingsRepository, MultiAccountSettingsRepository, @unchecked Sendable {
    private var enabledStates: [String: Bool] = [:]
    private var accountsByProvider: [String: [ProviderAccountConfig]] = [:]
    private var activeAccountIds: [String: String] = [:]

    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { enabledStates[id] ?? defaultValue }
    func isEnabled(forProvider id: String) -> Bool { enabledStates[id] ?? true }
    func setEnabled(_ enabled: Bool, forProvider id: String) { enabledStates[id] = enabled }
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
    func accounts(forProvider id: String) -> [ProviderAccountConfig] { accountsByProvider[id] ?? [] }
    func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        var existing = accountsByProvider[id] ?? []
        if !existing.contains(where: { $0.accountId == config.accountId }) {
            existing.append(config)
            accountsByProvider[id] = existing
        }
    }
    func removeAccount(accountId: String, forProvider id: String) {
        var existing = accountsByProvider[id] ?? []
        existing.removeAll { $0.accountId == accountId }
        accountsByProvider[id] = existing
    }
    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        var existing = accountsByProvider[id] ?? []
        if let index = existing.firstIndex(where: { $0.accountId == config.accountId }) {
            existing[index] = config
            accountsByProvider[id] = existing
        }
    }
    func activeAccountId(forProvider id: String) -> String? { activeAccountIds[id] }
    func setActiveAccountId(_ accountId: String?, forProvider id: String) { activeAccountIds[id] = accountId }
}
