import Foundation
import Observation
import Domain

/// User-triggered refresh, cancel, and result aggregation.
/// Background polling stays on `StatusItemLabelDriver` / `QuotaMonitor` until Task 10.
@MainActor
@Observable
public final class RefreshCoordinator: RefreshCoordinating {
    public private(set) var state: RefreshState = .idle
    public private(set) var lastSuccessCount: Int = 0
    public private(set) var lastFailureCount: Int = 0
    public private(set) var pausePolicy: RefreshPausePolicy = .active

    public let maxConcurrent: Int

    private let monitor: QuotaMonitor
    private let powerState: (any PowerStateProvider)?
    private var runTask: Task<Void, Never>?
    private var cancelRequested = false
    private var startedProviderIds: Set<String> = []
    private var powerEventsTask: Task<Void, Never>?

    public init(
        monitor: QuotaMonitor,
        powerState: (any PowerStateProvider)? = nil,
        maxConcurrent: Int = 2
    ) {
        self.monitor = monitor
        self.powerState = powerState
        self.maxConcurrent = max(1, maxConcurrent)
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

    public func applyPowerEvent(_ event: PowerEvent) {
        switch event {
        case .willSleep:
            pausePolicy = .asleep
        case .didWake:
            pausePolicy = powerState?.refreshPausePolicy() ?? .active
        }
    }

    public func refresh(_ scope: RefreshScope) async {
        await refresh(scope, skipFreshWithin: nil)
    }

    public func refresh(_ scope: RefreshScope, skipFreshWithin: TimeInterval?) async {
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
            await self.perform(scope: scope, skipFreshWithin: skipFreshWithin)
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
    }

    private func perform(scope: RefreshScope, skipFreshWithin: TimeInterval?) async {
        let ids = providerIds(for: scope)
        var success = 0
        var failure = 0
        var index = 0

        while index < ids.count {
            if cancelRequested { break }
            let end = min(index + maxConcurrent, ids.count)
            let wave = Array(ids[index..<end])
            index = end
            for id in wave {
                startedProviderIds.insert(id)
            }

            let outcomes = await refreshWave(wave, skipFreshWithin: skipFreshWithin)
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
        if cancelRequested {
            state = .cancelled(completedCount: success + failure)
        } else {
            state = .completed(successCount: success, failureCount: failure)
        }
    }

    private func refreshWave(
        _ ids: [String],
        skipFreshWithin: TimeInterval?
    ) async -> [ProviderRefreshResult] {
        var tasks: [Task<ProviderRefreshResult, Never>] = []
        tasks.reserveCapacity(ids.count)
        for id in ids {
            tasks.append(Task { await self.refreshOne(id, skipFreshWithin: skipFreshWithin) })
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

    private func refreshOne(_ id: String, skipFreshWithin: TimeInterval?) async -> ProviderRefreshResult {
        guard let provider = monitor.provider(for: id) else { return .skipped }
        if let ttl = skipFreshWithin,
           let captured = provider.snapshot?.capturedAt,
           Date().timeIntervalSince(captured) < ttl,
           provider.lastError == nil {
            return .succeeded
        }
        return await monitor.refreshResult(providerId: id, kind: .interactive)
    }
}
