import Testing
import Foundation
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
    private var continuations: [UUID: AsyncStream<PowerEvent>.Continuation] = [:]

    var isDisplayAsleep: Bool {
        lock.withLock { asleep }
    }

    var isOnBattery: Bool { false }

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
        lock.lock()
        asleep = value
        let listeners = Array(continuations.values)
        lock.unlock()
        for continuation in listeners {
            continuation.yield(value ? .willSleep : .didWake)
        }
    }
}
