import Testing
@testable import Domain

@Suite("RefreshInterval")
struct RefreshIntervalTests {
    @Test
    func `seconds mapping`() {
        #expect(RefreshInterval.off.seconds == nil)
        // Legacy oneMinute raw value maps to 5 min cadence for energy.
        #expect(RefreshInterval.oneMinute.seconds == 300)
        #expect(RefreshInterval.fiveMinutes.seconds == 300)
        #expect(RefreshInterval.tenMinutes.seconds == 600)
        #expect(RefreshInterval.fifteenMinutes.seconds == 900)
        #expect(RefreshInterval.thirtyMinutes.seconds == 1800)
    }

    @Test
    func `isEnabled`() {
        #expect(RefreshInterval.off.isEnabled == false)
        #expect(RefreshInterval.oneMinute.isEnabled == true)
        #expect(RefreshInterval.fiveMinutes.isEnabled == true)
        #expect(RefreshInterval.tenMinutes.isEnabled == true)
        #expect(RefreshInterval.fifteenMinutes.isEnabled == true)
        #expect(RefreshInterval.thirtyMinutes.isEnabled == true)
    }

    @Test
    func `labels are non-empty`() {
        for interval in RefreshInterval.pickerCases {
            #expect(!interval.label.isEmpty)
        }
    }

    @Test
    func `pickerCases exclude legacy oneMinute raw case`() {
        #expect(!RefreshInterval.pickerCases.contains(.oneMinute))
        #expect(RefreshInterval.pickerCases == [
            .off, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes,
        ])
    }

    @Test
    func `migrating disabled is off`() {
        #expect(RefreshInterval.migrating(enabled: false, storedSeconds: 60) == .off)
        #expect(RefreshInterval.migrating(enabled: false, storedSeconds: 900) == .off)
    }

    @Test
    func `migrating snaps to nearest power-friendly option`() {
        // Short legacy values collapse to 5 min (no 1-min UI option).
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 30) == .fiveMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 60) == .fiveMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 120) == .fiveMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 300) == .fiveMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 600) == .tenMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 700) == .tenMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 900) == .fifteenMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 1800) == .thirtyMinutes)
    }
}
