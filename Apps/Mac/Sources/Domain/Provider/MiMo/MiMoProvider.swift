import Foundation
import Observation

/// Xiaomi MiMo Token Plan provider — monthly credits from the open platform console.
@MainActor
@Observable
public final class MiMoProvider: AIProvider {
    public let id: String = "mimo"
    public let name: String = "Xiaomi MiMo"
    public let cliCommand: String = "mimo-token-plan"

    public var dashboardURL: URL? {
        URL(string: "https://platform.xiaomimimo.com/console/plan-manage")
    }

    public var statusPageURL: URL? { nil }

    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    private let probe: any UsageProbe
    private let settingsRepository: any MiMoSettingsRepository

    public init(probe: any UsageProbe, settingsRepository: any MiMoSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        // Opt-in: requires browser login / cookie
        self.isEnabled = settingsRepository.isEnabled(forProvider: "mimo", defaultValue: false)
    }

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await probe.probe()
            snapshot = newSnapshot
            lastError = nil
            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }
}
