import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite("智额 product defaults")
@MainActor
struct SmartQuotaProductDefaultsTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    @Test("selected provider defaults to codex")
    func selectedProviderDefaultsToCodex() {
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: []),
            alerter: nil,
            clock: TestClock()
        )
        #expect(monitor.selectedProviderId == "codex")
    }
}
