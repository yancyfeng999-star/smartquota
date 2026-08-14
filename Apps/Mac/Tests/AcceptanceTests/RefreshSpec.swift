import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Refresh
///
/// Users refresh quota data manually or via background sync.
///
/// Behaviors covered:
/// - #15: User clicks Refresh → fetches latest quota for current provider
/// - #16: Button shows "Syncing..." spinner while in progress
/// - #17: Duplicate refresh clicks are ignored while syncing
/// - #18: Background sync auto-refreshes at configured interval
/// - Current membership, refresh-all, cancel, and partial failure go through RefreshCoordinator
@Suite("Feature: Refresh")
struct RefreshSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private static func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - #15: Successful refresh

    @Suite("Scenario: Successful refresh")
    @MainActor
    struct SuccessfulRefresh {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `refresh updates snapshot with fresh data`() async {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            #expect(claude.snapshot == nil)

            // When — user clicks Refresh
            await monitor.refresh(providerId: "claude")

            // Then
            #expect(claude.snapshot != nil)
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 65)
        }

        @Test
        func `failed refresh stores error without affecting other providers`() async {
            // Given
            let settings = RefreshSpec.makeSettings()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            given(codexProbe).isAvailable().willReturn(true)
            given(codexProbe).probe().willThrow(ProbeError.timeout)

            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // When
            await monitor.refreshAll()

            // Then — Claude succeeds, Codex fails independently
            #expect(claude.snapshot != nil)
            #expect(codex.snapshot == nil)
            #expect(codex.lastError != nil)
        }
    }

    // MARK: - #18: Background sync

    @Suite("Scenario: Background sync")
    @MainActor
    struct BackgroundSync {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `continuous monitoring emits refresh events`() async throws {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — start monitoring
            let stream = monitor.startMonitoring(interval: .milliseconds(100))
            var events: [MonitoringEvent] = []

            for await event in stream.prefix(2) {
                events.append(event)
            }

            monitor.stopMonitoring()

            // Then — received refresh events
            #expect(events.count == 2)
            #expect(events.allSatisfy { if case .refreshed = $0 { return true }; return false })
        }

        @Test
        func `monitoring stops when requested`() async throws {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — start then immediately stop
            let stream = monitor.startMonitoring(interval: .milliseconds(50))
            monitor.stopMonitoring()

            var eventCount = 0
            for await _ in stream {
                eventCount += 1
            }

            // Then — stream finishes quickly
            #expect(eventCount <= 2)
        }

        // MARK: - #204: Power-conscious background refresh

        /// A clock that records each requested sleep, then ends the loop by
        /// throwing — so one deterministic tick reveals the background cadence.
        private final class RecordingClock: Clock, @unchecked Sendable {
            private let lock = NSLock()
            private var _durations: [Duration] = []
            var durations: [Duration] { lock.withLock { _durations } }
            func sleep(for duration: Duration) async throws {
                lock.withLock { _durations.append(duration) }
                throw CancellationError()
            }
            func sleep(nanoseconds: UInt64) async throws {
                try await sleep(for: .nanoseconds(Int64(nanoseconds)))
            }
        }

        /// Minimal `ClaudeSettingsRepository` fixing the probe mode, so a scenario
        /// can exercise API-mode background behavior end-to-end.
        private final class ClaudeModeSettings: ClaudeSettingsRepository, @unchecked Sendable {
            let mode: ClaudeProbeMode
            init(mode: ClaudeProbeMode) { self.mode = mode }
            func isEnabled(forProvider id: String) -> Bool { true }
            func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { true }
            func setEnabled(_ enabled: Bool, forProvider id: String) {}
            func customCardURL(forProvider id: String) -> String? { nil }
            func setCustomCardURL(_ url: String?, forProvider id: String) {}
            func claudeProbeMode() -> ClaudeProbeMode { mode }
            func setClaudeProbeMode(_ mode: ClaudeProbeMode) {}
            func claudeCliFallbackEnabled() -> Bool { true }
            func setClaudeCliFallbackEnabled(_ enabled: Bool) {}
        }

        /// A probe that returns the next snapshot in a sequence on each call, so a
        /// test can tell successive refreshes apart by their data.
        private final class SequentialProbe: UsageProbe, @unchecked Sendable {
            private let lock = NSLock()
            private var index = 0
            private let snapshots: [UsageSnapshot]
            init(_ snapshots: [UsageSnapshot]) { self.snapshots = snapshots }
            func probe() async throws -> UsageSnapshot {
                lock.withLock {
                    let snapshot = snapshots[min(index, snapshots.count - 1)]
                    index += 1
                    return snapshot
                }
            }
            func isAvailable() async -> Bool { true }
        }

        @Test
        func `CLI mode keeps auto-refreshing in the background`() async {
            // Given — a CLI-mode Claude provider (base settings → CLI).
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 42, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))
            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — background sync runs a cycle.
            let stream = monitor.startMonitoring(interval: .seconds(600))
            for await _ in stream.prefix(1) {}
            monitor.stopMonitoring()

            // Then — it refreshed via the CLI probe (no silent CLI→API swap).
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 42)
        }

        @Test
        func `API mode background cadence is at least 15 minutes`() async {
            // Given — API-mode Claude and a user who picked the 1-minute option.
            let settings = ClaudeModeSettings(mode: .api)
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            )
            let cliProbe = MockUsageProbe()
            given(cliProbe).isAvailable().willReturn(true)
            given(cliProbe).probe().willReturn(snapshot)
            let apiProbe = MockUsageProbe()
            given(apiProbe).isAvailable().willReturn(true)
            given(apiProbe).probe().willReturn(snapshot)
            let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)
            let clock = RecordingClock()
            let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: clock)

            // When — background sync runs one tick.
            let stream = monitor.startMonitoring(interval: .seconds(60), providerIds: ["claude"])
            for await _ in stream {}

            // Then — the cadence is floored to the 15-minute API cache TTL (#204).
            #expect(clock.durations == [.seconds(900)])
        }

        @Test
        func `interactive refresh is not throttled by the API background floor`() async {
            // Given — an API-mode Claude provider (which imposes a 15-min background
            // floor) returning a different snapshot on each probe.
            let settings = ClaudeModeSettings(mode: .api)
            let probe = SequentialProbe([
                UsageSnapshot(
                    providerId: "claude",
                    quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")],
                    capturedAt: Date()
                ),
                UsageSnapshot(
                    providerId: "claude",
                    quotas: [UsageQuota(percentRemaining: 60, quotaType: .session, providerId: "claude")],
                    capturedAt: Date()
                ),
            ])
            let claude = ClaudeProvider(cliProbe: MockUsageProbe(), apiProbe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: TestClock())

            // When/Then — two back-to-back user-initiated refreshes both update the
            // snapshot. The 15-min floor governs only the background loop, never the
            // interactive path (#204), so neither call is gated.
            await monitor.refresh(providerId: "claude")
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 80)
            await monitor.refresh(providerId: "claude")
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 60)
        }
    }

    // MARK: - Coordinator: current / all / cancel / partial failure

    @Suite("Scenario: Refresh coordinator")
    @MainActor
    struct CoordinatorRefresh {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `current membership refresh only updates the selected provider`() async {
            let settings = RefreshSpec.makeSettings()
            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 10, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))
            let codexProbe = MockUsageProbe()
            given(codexProbe).isAvailable().willReturn(true)
            given(codexProbe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 90, quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            ))
            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )
            monitor.selectedProviderId = "codex"
            let coordinator = RefreshCoordinator(monitor: monitor)

            await coordinator.refresh(.provider(monitor.selectedProviderId))

            #expect(await coordinator.state == .completed(successCount: 1, failureCount: 0))
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 90)
            #expect(claude.snapshot == nil)
        }

        @Test
        func `refresh all shows success and failure counts without clearing the failed snapshot`() async {
            let settings = RefreshSpec.makeSettings()
            let captured = Date(timeIntervalSince1970: 50)
            let claudeProbe = AcceptanceScriptedProbe(
                providerId: "claude",
                steps: [.success(70)]
            )
            let codexProbe = AcceptanceScriptedProbe(
                providerId: "codex",
                steps: [.success(40, capturedAt: captured), .failure(ProbeError.timeout)]
            )
            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )
            await monitor.refresh(providerId: "codex")

            let coordinator = RefreshCoordinator(monitor: monitor)
            await coordinator.refresh(.allEnabledProviders)

            #expect(await coordinator.state == .completed(successCount: 1, failureCount: 1))
            #expect(claude.snapshot != nil)
            #expect(codex.snapshot?.capturedAt == captured)
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 40)
            #expect((codex.lastError as? ProbeError) == .timeout)
        }

        @Test
        func `cancel keeps finished work and does not start the remaining member`() async {
            let hold = AcceptanceReleaseGate()
            let started = AcceptanceStartGate()
            let claudeProbe = AcceptanceScriptedProbe(
                providerId: "claude",
                steps: [.success(80), .success(15)]
            )
            let codexProbe = AcceptanceScriptedProbe(
                providerId: "codex",
                steps: [.success(60), .wait(hold, error: ProbeError.timeout)],
                onStart: { await started.mark() }
            )
            let geminiProbe = AcceptanceScriptedProbe(
                providerId: "gemini",
                steps: [.success(50), .success(1)],
                onStart: { await started.mark() }
            )
            let settings = RefreshSpec.makeSettings()
            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let gemini = GeminiProvider(probe: geminiProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex, gemini]),
                clock: TestClock()
            )
            let coordinator = RefreshCoordinator(monitor: monitor, maxConcurrent: 2)

            await coordinator.refresh(.allEnabledProviders)
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 80)

            await started.reset()
            let run = Task { await coordinator.refresh(.allEnabledProviders) }
            await started.wait(until: 1)
            await coordinator.cancel()
            await hold.release()
            await run.value

            #expect(await coordinator.state == .cancelled(completedCount: 2))
            #expect(coordinator.lastSuccessCount == 1)
            #expect(coordinator.lastFailureCount == 1)
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 15)
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 60)
            #expect(gemini.snapshot?.quotas.first?.percentRemaining == 50)
            #expect(await geminiProbe.starts() == 1)
            #expect(coordinator.didStartProvider("gemini") == false)
        }
    }
}

private actor AcceptanceStartGate {
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

    func reset() {
        count = 0
    }
}

private actor AcceptanceReleaseGate {
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

private final class AcceptanceScriptedProbe: UsageProbe, @unchecked Sendable {
    enum Step {
        case success(Double, capturedAt: Date = Date())
        case failure(Error)
        case wait(AcceptanceReleaseGate, error: Error)
    }

    let providerId: String
    private let lock = NSLock()
    private var steps: [Step]
    private var startCount = 0
    private let onStart: (@Sendable () async -> Void)?

    init(providerId: String, steps: [Step], onStart: (@Sendable () async -> Void)? = nil) {
        self.providerId = providerId
        self.steps = steps
        self.onStart = onStart
    }

    func starts() async -> Int { lock.withLock { startCount } }

    func probe() async throws -> UsageSnapshot {
        let step = lock.withLock { () -> Step in
            startCount += 1
            return steps.isEmpty ? Step.success(0) : steps.removeFirst()
        }
        if let onStart { await onStart() }
        switch step {
        case let .success(percent, capturedAt):
            return UsageSnapshot(
                providerId: providerId,
                quotas: [UsageQuota(percentRemaining: percent, quotaType: .session, providerId: providerId)],
                capturedAt: capturedAt
            )
        case let .failure(error):
            throw error
        case let .wait(gate, error):
            await gate.wait()
            throw error
        }
    }

    func isAvailable() async -> Bool { true }
}
