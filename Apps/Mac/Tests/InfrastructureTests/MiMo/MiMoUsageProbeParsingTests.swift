import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("MiMo Token Plan parsing")
struct MiMoUsageProbeParsingTests {

    static let detailJSON = """
    {
      "code": 0,
      "message": "",
      "data": {
        "planCode": "max",
        "planName": "Max",
        "currentPeriodEnd": "2026-08-25 23:59:59",
        "expired": false
      }
    }
    """

    static let usageJSON = """
    {
      "code": 0,
      "message": "",
      "data": {
        "monthUsage": {
          "percent": 0.0712,
          "items": [
            {
              "name": "month_total_token",
              "used": 5838807059,
              "limit": 82000000000,
              "percent": 0.0712
            }
          ]
        },
        "usage": {
          "percent": 0.07,
          "items": [
            {
              "name": "plan_total_token",
              "used": 5838807059,
              "limit": 82000000000,
              "percent": 0.07
            },
            {
              "name": "compensation_total_token",
              "used": 0,
              "limit": 0,
              "percent": 0
            }
          ]
        }
      }
    }
    """

    @Test
    func `parses token plan remaining and Max tier`() throws {
        let snapshot = try MiMoUsageProbe.buildSnapshot(
            detailData: Data(Self.detailJSON.utf8),
            usageData: Data(Self.usageJSON.utf8),
            providerId: "mimo"
        )

        #expect(snapshot.providerId == "mimo")
        #expect(snapshot.quotas.count == 1)
        let quota = try #require(snapshot.quotas.first)
        // used 7% → remaining ~93%
        #expect(quota.percentRemaining > 92 && quota.percentRemaining < 94)
        #expect(quota.compactTitle == "Token Plan")
        if case .timeLimit(let name) = quota.quotaType {
            #expect(name == "Monthly")
        } else {
            Issue.record("expected monthly timeLimit")
        }
        #expect(snapshot.accountTier?.badgeText.contains("Max") == true)
        #expect(quota.resetsAt != nil)
        // No cash balance in snapshot
        #expect(snapshot.costUsage == nil)
    }

    @Test
    func `normalize cookie requires serviceToken and userId`() {
        let ok = MiMoUsageProbe.normalizeCookieHeader(
            "api-platform_serviceToken=tok; userId=123; api-platform_ph=x"
        )
        #expect(ok?.contains("api-platform_serviceToken=tok") == true)
        #expect(ok?.contains("userId=123") == true)

        let bad = MiMoUsageProbe.normalizeCookieHeader("userId=123")
        #expect(bad == nil)
    }

    @Test
    func `detail error code throws`() {
        let badDetail = """
        {"code": 401, "message": "login required", "data": null}
        """
        #expect(throws: ProbeError.self) {
            try MiMoUsageProbe.buildSnapshot(
                detailData: Data(badDetail.utf8),
                usageData: Data(Self.usageJSON.utf8),
                providerId: "mimo"
            )
        }
    }
}
