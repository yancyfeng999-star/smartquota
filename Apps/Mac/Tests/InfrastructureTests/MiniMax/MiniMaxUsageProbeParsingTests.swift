import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct MiniMaxUsageProbeParsingTests {

    // MARK: - Sample Data

    /// Legacy request-count shape (older MiniMax coding plan responses)
    static let sampleSuccessResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 255,
          "remains_time": 1234,
          "end_time": 1735689600000
        }
      ]
    }
    """

    static let sampleMultiModelResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 255,
          "remains_time": 1234,
          "end_time": 1735689600000
        },
        {
          "model_name": "minimax-m1",
          "current_interval_total_count": 500,
          "current_interval_usage_count": 400,
          "remains_time": 1234,
          "end_time": 1735689600000
        }
      ]
    }
    """

    static let sampleErrorResponse = """
    {
      "base_resp": { "status_code": 1001, "status_msg": "invalid api key" },
      "model_remains": []
    }
    """

    static let sampleEmptyRemainsResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": []
    }
    """

    static let sampleNoEndTimeResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1000,
          "current_interval_usage_count": 500
        }
      ]
    }
    """

    /// Live CN Token Plan shape (percent-based 5h + weekly)
    static let samplePercentResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "general",
          "start_time": 1785772800000,
          "end_time": 1785790800000,
          "current_interval_remaining_percent": 99,
          "current_weekly_remaining_percent": 99,
          "weekly_start_time": 1785686400000,
          "weekly_end_time": 1786291200000,
          "current_interval_status": 1,
          "current_weekly_status": 1,
          "current_interval_total_count": 0,
          "current_interval_usage_count": 0
        },
        {
          "model_name": "video",
          "start_time": 1785772800000,
          "end_time": 1785859200000,
          "current_interval_remaining_percent": 100,
          "current_weekly_remaining_percent": 85,
          "current_interval_total_count": 3,
          "current_interval_usage_count": 0,
          "current_weekly_total_count": 21,
          "current_weekly_usage_count": 3,
          "weekly_start_time": 1785686400000,
          "weekly_end_time": 1786291200000,
          "current_interval_status": 1,
          "current_weekly_status": 1
        }
      ]
    }
    """

    // MARK: - Legacy count-based parsing

    @Test
    func `parses model_remains into session quota`() throws {
        let data = Data(Self.sampleSuccessResponse.utf8)
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .session)
        #expect(snapshot.providerId == "minimax")
    }

    @Test
    func `maps percentage correctly from remaining count`() throws {
        // usage_count=255 is REMAINING → 255/1500
        let data = Data(Self.sampleSuccessResponse.utf8)
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        let expected = Double(255) / Double(1500) * 100.0
        #expect(snapshot.quotas[0].percentRemaining == expected)
    }

    @Test
    func `parses reset time from end_time millisecond timestamp`() throws {
        let data = Data(Self.sampleSuccessResponse.utf8)
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        let expectedDate = Date(timeIntervalSince1970: 1735689600.0)
        #expect(snapshot.quotas[0].resetsAt == expectedDate)
    }

    @Test
    func `handles multiple models with legacy counts`() throws {
        let data = Data(Self.sampleMultiModelResponse.utf8)
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        // primary → session; non-video secondary (minimax-m1) is intentionally skipped
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .session)
    }

    @Test
    func `handles error response with non-zero status_code`() throws {
        let data = Data(Self.sampleErrorResponse.utf8)
        #expect(throws: ProbeError.self) {
            try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")
        }
    }

    @Test
    func `handles empty model_remains`() throws {
        let data = Data(Self.sampleEmptyRemainsResponse.utf8)
        #expect(throws: ProbeError.noData) {
            try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")
        }
    }

    @Test
    func `generates reset text with usage counts`() throws {
        let data = Data(Self.sampleSuccessResponse.utf8)
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")
        // remaining=255 → used = 1500 - 255 = 1245
        #expect(snapshot.quotas[0].resetText == "1245/1500 requests")
    }

    @Test
    func `handles missing end_time gracefully`() throws {
        let data = Data(Self.sampleNoEndTimeResponse.utf8)
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")
        #expect(snapshot.quotas[0].resetsAt == nil)
        #expect(snapshot.quotas[0].percentRemaining == 50.0)
    }

    @Test
    func `throws parseFailed on invalid JSON`() throws {
        let data = Data("not json".utf8)
        #expect(throws: ProbeError.self) {
            try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")
        }
    }

    // MARK: - Percent-based CN Token Plan

    @Test
    func `parses percent-based general 5h and weekly quotas`() throws {
        let data = Data(Self.samplePercentResponse.utf8)
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        let session = snapshot.quotas.first { $0.quotaType == .session }
        let weekly = snapshot.quotas.first { $0.quotaType == .weekly }
        let video = snapshot.quotas.first { $0.quotaType == .modelSpecific("video") }

        #expect(session?.percentRemaining == 99)
        #expect(weekly?.percentRemaining == 99)
        #expect(video?.percentRemaining == 100)
        // Live CN plan: video is count-based (3/day), not 100/100 percent only
        #expect(video?.resetText == "剩余 3/3 条")
        #expect(video?.compactTitle == "视频")

        #expect(session?.resetsAt == Date(timeIntervalSince1970: 1785790800.0))
        #expect(weekly?.resetsAt == Date(timeIntervalSince1970: 1786291200.0))
        #expect(session?.windowDuration == Double(5 * 3600))
        #expect(weekly?.windowDuration == Double(7 * 24 * 3600))
    }
}
