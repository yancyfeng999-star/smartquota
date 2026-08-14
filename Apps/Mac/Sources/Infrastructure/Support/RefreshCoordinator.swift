import Foundation
import Observation
import Domain

/// User-triggered and background refresh, cancel, retry, and result aggregation.
/// Providers must not own uncancelable Timers; this type is the only scheduler.
@MainActor
@Observable
public final class RefreshCoordinator: RefreshCoordinating {
    public private(set) var state: RefreshState = .idle
    public private(set) var lastSuccessCount: Int = 0
    public private(set) var lastFailureCount: Int = 0
    public private(set) var pausePolicy: RefreshPausePolicy = .active
    public private(set) var isBackgroundRefreshRunning = false
    public private(set) var backgroundTickCount = 0

    public let maxConcurrent: Int
    public let performance: RefreshPerformanceMonitor

    private let monitor: QuotaMonitor
    private let powerState: (any PowerStateProvider)?
    private let clock: any Clock
    private let interactivePolicy: RefreshExecutionPolicy
    private let backgroundPolicy: RefreshExecutionPolicy

    private var runTask: Task<Void, Never>?
    private var backgroundLoopTask: Task<Void, Never>?
    private var powerEventsTask: Task<Void, Never>?
    private var cancelRequested = false
    private var startedProviderIds: Set<String> = []
    private var tickWaiters: [CheckedContinuation<Void, Never>] = []

    private var backgroundEnabled = false
    private var backgroundInterval: Duration = .seconds(900)
    private var backgroundProviderIds: [String]?
    private var backgroundLoopGeneration = 0

    public init(
        monitor: QuotaMonitor,
        powerState: (any PowerStateProvider)? = nil,
        maxConcurrent: Int = 2,
        clock: any Clock = SystemClock(),
        performance: RefreshPerformanceMonitor = RefreshPerformanceMonitor(),
        backgroundPolicy: RefreshExecutionPolicy = .background,
        interactivePolicy: RefreshExecutionPolicy = .interactive
    ) {
        self.monitor = monitor
        self.powerState = powerState
        self.maxConcurrent = max(1, maxConcurrent)
        self.clock = clock
        self.performance = performance
        self.backgroundPolicy = backgroundPolicy
        self.interactivePolicy = interactivePolicy
        if let powerState {
            pausePolicy = powerState.refreshPausePolicy()
            powerEventsTask = Task { [weak self] in
                for await event in powerState.events() {
                    self?.applyPowerEvent(event)
                }
            }
        }
    }

    public func didStartProvider(_ id: String) -> Bool {
        startedProviderIds.contains(id)
    }

    public func historicalSnapshot(providerId: String, accountId: String? = nil) -> UsageSnapshot? {
        monitor.historicalSnapshot(providerId: providerId, accountId: accountId)
    }

    public func applyPowerEvent(_ event: PowerEvent) {
        switch event {
        case .willSleep:
            if let policy = powerState?.refreshPausePolicy(), policy.pauseBackgroundRefresh {
                pausePolicy = policy
            } else {
                pausePolicy = .asleep
            }
            stopBackgroundLoop()
        case .didWake:
            pausePolicy = powerState?.refreshPausePolicy() ?? .active
            guard backgroundEnabled, !pausePolicy.pauseBackgroundRefresh else { return }
            startBackgroundLoopIfNeeded()
        }
    }

    public func setBackgroundRefresh(
        enabled: Bool,
        interval: Duration,
        providerIds: [String]?
    ) {
        backgroundEnabled = enabled
        backgroundInterval = interval
        backgroundProviderIds = providerIds
        if !enabled || pausePolicy.pauseBackgroundRefresh {
            stopBackgroundLoop()
            return
        }
        restartBackgroundLoop()
    }

    public func stopBackgroundRefresh() {
        backgroundEnabled = false
        stopBackgroundLoop()
    }

    public func waitUntilBackgroundTickCount(_ count: Int) async {
        while backgroundTickCount < count {
            await withCheckedContinuation { tickWaiters.append($0) }
        }
    }

    public func refresh(_ scope: RefreshScope) async {
        await refresh(scope, policy: interactivePolicy)
    }

    public func refresh(_ scope: RefreshScope, skipFreshWithin: TimeInterval?) async {
        var policy = interactivePolicy
        policy.mergeWindow = skipFreshWithin
        await refresh(scope, policy: policy)
    }

    public func refresh(_ scope: RefreshScope, policy: RefreshExecutionPolicy) async {
        if let runTask {
            switch state {
            case let .running(current, _):
                if scope.shouldReuse(existing: current) {
                    await runTask.value
                }
                return
            case .cancelling:
                return
            default:
                break
            }
        }

        cancelRequested = false
        startedProviderIds.removeAll()
        lastSuccessCount = 0
        lastFailureCount = 0
        state = .running(scope: scope, startedAt: Date())

        let task = Task { @MainActor in
            await self.perform(scope: scope, ids: nil, policy: policy)
        }
        runTask = task
        await task.value
        if !state.isBusy {
            runTask = nil
        }
    }

    public func cancel() async {
        guard state.isBusy else { return }
        cancelRequested = true
        state = .cancelling
        performance.recordCancel()
        monitor.cancelInFlightRefreshes()
    }

    // MARK: - Background loop

    private func restartBackgroundLoop() {
        stopBackgroundLoop()
        startBackgroundLoopIfNeeded()
    }

    private func startBackgroundLoopIfNeeded() {
        guard backgroundEnabled, !pausePolicy.pauseBackgroundRefresh else { return }
        guard backgroundLoopTask == nil else { return }
        backgroundLoopGeneration += 1
        let generation = backgroundLoopGeneration
        isBackgroundRefreshRunning = true
        backgroundLoopTask = Task { [weak self] in
            await self?.runBackgroundLoop(generation: generation)
        }
    }

    private func stopBackgroundLoop() {
        backgroundLoopGeneration += 1
        backgroundLoopTask?.cancel()
        backgroundLoopTask = nil
        isBackgroundRefreshRunning = false
    }

    private func runBackgroundLoop(generation: Int) async {
        defer {
            if backgroundLoopGeneration == generation {
                isBackgroundRefreshRunning = false
                backgroundLoopTask = nil
            }
        }
        while !Task.isCancelled, backgroundEnabled, !pausePolicy.pauseBackgroundRefresh {
            await performBackgroundTick()
            if Task.isCancelled || !backgroundEnabled || pausePolicy.pauseBackgroundRefresh {
                break
            }
            let sleepInterval = currentBackgroundSleepInterval()
            do {
                try await clock.sleep(for: sleepInterval)
            } catch {
                break
            }
        }
    }

    private func performBackgroundTick() async {
        let ids = resolvedBackgroundProviderIds()
        if ids.isEmpty {
            noteBackgroundTick()
            return
        }
        let scope: RefreshScope = ids.count == 1 ? .provider(ids[0]) : .allEnabledProviders
        if let runTask, state.isBusy {
            if case let .running(current, _) = state, scope.shouldReuse(existing: current) {
                await runTask.value
            }
            noteBackgroundTick()
            return
        }
        await refresh(scope: scope, ids: ids, policy: backgroundPolicy)
        noteBackgroundTick()
    }

    private func refresh(scope: RefreshScope, ids: [String], policy: RefreshExecutionPolicy) async {
        if let runTask, state.isBusy {
            if case let .running(current, _) = state, scope.shouldReuse(existing: current) {
                await runTask.value
            }
            return
        }
        cancelRequested = false
        startedProviderIds.removeAll()
        lastSuccessCount = 0
        lastFailureCount = 0
        state = .running(scope: scope, startedAt: Date())
        let task = Task { @MainActor in
            await self.perform(scope: scope, ids: ids, policy: policy)
        }
        runTask = task
        await task.value
        if !state.isBusy {
            runTask = nil
        }
    }

    private func currentBackgroundSleepInterval() -> Duration {
        let ids = resolvedBackgroundProviderIds()
        let floors = ids.compactMap { monitor.provider(for: $0)?.backgroundRefreshFloor }
        var interval = QuotaMonitor.effectiveInterval(requested: backgroundInterval, floors: floors)
        if powerState?.isOnBattery == true {
            interval = interval * QuotaMonitor.batteryIntervalMultiplier
        }
        return interval
    }

    private func resolvedBackgroundProviderIds() -> [String] {
        let enabled = Set(monitor.enabledProviders.map(\.id))
        if let backgroundProviderIds {
            return backgroundProviderIds.filter { enabled.contains($0) }
        }
        if enabled.contains(monitor.selectedProviderId) {
            return [monitor.selectedProviderId]
        }
        return []
    }

    private func noteBackgroundTick() {
        backgroundTickCount += 1
        let waiters = tickWaiters
        tickWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    // MARK: - Run

    private func perform(
        scope: RefreshScope,
        ids: [String]?,
        policy: RefreshExecutionPolicy
    ) async {
        let startedAt = ContinuousClock.now
        let providerIds = (ids ?? providerIds(for: scope)).filter { id in
            monitor.provider(for: id)?.isEnabled == true
        }
        var success = 0
        var failure = 0
        var index = 0
        performance.setInFlight(0)

        while index < providerIds.count {
            if cancelRequested || Task.isCancelled { break }
            let end = min(index + maxConcurrent, providerIds.count)
            let wave = Array(providerIds[index..<end])
            index = end
            for id in wave {
                startedProviderIds.insert(id)
            }
            performance.setInFlight(wave.count)

            let outcomes = await refreshWave(wave, policy: policy)
            for result in outcomes {
                switch result {
                case .succeeded:
                    success += 1
                case .failed:
                    failure += 1
                case .skipped:
                    break
                }
            }
        }

        lastSuccessCount = success
        lastFailureCount = failure
        performance.setInFlight(0)
        let duration = ContinuousClock.now - startedAt
        let cancelled = cancelRequested || Task.isCancelled
        if cancelled {
            state = .cancelled(completedCount: success + failure)
        } else {
            state = .completed(successCount: success, failureCount: failure)
        }
        performance.recordRun(
            duration: duration,
            taskCount: providerIds.count,
            cancelled: cancelled,
            failureKinds: failureKindsFromRun(providerIds)
        )
    }

    private func failureKindsFromRun(_ ids: [String]) -> [RefreshFailureKind] {
        ids.compactMap { id in
            guard let error = monitor.provider(for: id)?.lastError else { return nil }
            return RefreshFailureClassifier.classify(error)
        }
    }

    private func refreshWave(
        _ ids: [String],
        policy: RefreshExecutionPolicy
    ) async -> [ProviderRefreshResult] {
        var tasks: [Task<ProviderRefreshResult, Never>] = []
        tasks.reserveCapacity(ids.count)
        for id in ids {
            tasks.append(Task { await self.refreshOne(id, policy: policy) })
        }
        var results: [ProviderRefreshResult] = []
        results.reserveCapacity(tasks.count)
        for task in tasks {
            results.append(await task.value)
        }
        return results
    }

    private func providerIds(for scope: RefreshScope) -> [String] {
        switch scope {
        case let .provider(id):
            guard let provider = monitor.provider(for: id), provider.isEnabled else { return [] }
            return [id]
        case .allEnabledProviders:
            return monitor.enabledProviders.map(\.id)
        }
    }

    private func refreshOne(_ id: String, policy: RefreshExecutionPolicy) async -> ProviderRefreshResult {
        guard let provider = monitor.provider(for: id), provider.isEnabled else { return .skipped }
        if let ttl = policy.mergeWindow,
           let captured = provider.snapshot?.capturedAt,
           Date().timeIntervalSince(captured) < ttl,
           provider.lastError == nil {
            return .succeeded
        }

        var lastResult: ProviderRefreshResult = .failed
        for attempt in 1...policy.maxAttempts {
            if cancelRequested || Task.isCancelled { return lastResult }
            let timed = await timedRefresh(id, policy: policy)
            switch timed {
            case .timedOut:
                lastResult = .failed
                return .failed
            case let .completed(result):
                lastResult = result
                if result != .failed { return result }
            }
            guard attempt < policy.maxAttempts else { break }
            guard shouldRetry(providerId: id) else { break }
            do {
                try await clock.sleep(for: policy.backoff(forAttempt: attempt))
            } catch {
                break
            }
        }
        return lastResult
    }

    private func shouldRetry(providerId: String) -> Bool {
        guard let error = monitor.provider(for: providerId)?.lastError else { return false }
        return RefreshFailureClassifier.classify(error) == .connectionFailed
    }

    private enum TimedRefresh {
        case completed(ProviderRefreshResult)
        case timedOut
    }

    private func timedRefresh(_ id: String, policy: RefreshExecutionPolicy) async -> TimedRefresh {
        guard let timeout = policy.requestTimeout else {
            let result = await monitor.refreshResult(providerId: id, kind: policy.kind)
            return .completed(result)
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<TimedRefresh, Never>) in
            let box = ResumeBox()
            let timeoutTask = Task { @MainActor in
                do {
                    try await self.clock.sleep(for: timeout)
                    if box.take() {
                        self.monitor.cancelInFlightRefreshes(providerId: id)
                        self.performance.recordCancel()
                        self.performance.recordFailure(.connectionFailed)
                        continuation.resume(returning: .timedOut)
                    }
                } catch {
                    // Sleep cancelled because the probe finished first, or the run ended.
                }
            }
            Task { @MainActor in
                let result = await self.monitor.refreshResult(providerId: id, kind: policy.kind)
                timeoutTask.cancel()
                if box.take() {
                    continuation.resume(returning: .completed(result))
                }
            }
        }
    }
}

/// First-writer-wins flag so a timeout race resumes the continuation once.
private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}
