import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct CodexUsageProbeTests {

    @Test
    func `isAvailable returns true when client finds binary`() async {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).isAvailable().willReturn(true)
        let probe = CodexUsageProbe(client: mockClient)

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when client cannot find binary`() async {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).isAvailable().willReturn(false)
        let probe = CodexUsageProbe(client: mockClient)

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `stripANSICodes removes colors`() {
        let input = "\u{1B}[32mGreen\u{1B}[0m Text"
        #expect(CodexUsageProbe.stripANSICodes(input) == "Green Text")
    }

    @Test
    func `extractUsageError finds common errors`() {
        #expect(CodexUsageProbe.extractUsageError("data not available yet") != nil)
        #expect(CodexUsageProbe.extractUsageError("Update available: 1.2.1 ... codex") == .updateRequired)
        #expect(CodexUsageProbe.extractUsageError("All good") == nil)
    }
}

// MARK: - Probe Tests

@Suite
struct CodexUsageProbeRPCTests {

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-rpc-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createAuthFile(
        at directory: URL,
        accessToken: String = "test-token",
        refreshToken: String = "test-refresh",
        accountId: String? = nil,
        idToken: String? = nil
    ) throws {
        let codexDir = directory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        var tokens: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken
        ]
        if let accountId { tokens["account_id"] = accountId }
        if let idToken { tokens["id_token"] = idToken }

        let auth: [String: Any] = ["tokens": tokens]
        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
        try data.write(to: codexDir.appendingPathComponent("auth.json"))
    }

    private func makeJWT(payload: [String: Any]) -> String {
        let header = Data("{\"alg\":\"RS256\",\"typ\":\"JWT\"}".utf8)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let headerB64 = header.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payloadB64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(headerB64).\(payloadB64).fakesig"
    }

    @Test
    func `probe returns snapshot from client`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 30, resetDescription: "Resets in 2h"),
                secondary: CodexRateLimitWindow(usedPercent: 50, resetDescription: "Resets in 3d"),
                planType: "pro"
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.providerId == "codex")
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.sessionQuota?.percentRemaining == 70) // 100 - 30
        #expect(snapshot.weeklyQuota?.percentRemaining == 50) // 100 - 50
    }

    @Test
    func `probe returns only primary quota when secondary is nil`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 25, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.weeklyQuota == nil)
    }

    @Test
    func `probe handles free plan with zero usage`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 0, resetDescription: "Free plan"),
                secondary: nil,
                planType: "free"
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 100)
    }

    @Test
    func `probe clamps negative percent remaining to zero`() async throws {
        // Given - usage over 100%
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 110, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 0) // max(0, 100-110)
    }

    @Test
    func `probe shuts down client after fetch`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 50, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        _ = try await probe.probe()

        // Then - verify shutdown was called
        verify(mockClient).shutdown().called(.atLeastOnce)
    }

    // MARK: - Account Identity Tests (RPC mode)

    @Test
    func `probe sets accountExternalId from credentials with email`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let idToken = makeJWT(payload: ["email": "rpc-user@example.com"])
        try createAuthFile(at: tempDir, accountId: "acc-rpc", idToken: idToken)

        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 20, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexUsageProbe(client: mockClient, credentialLoader: loader)

        let snapshot = try await probe.probe()

        #expect(snapshot.accountExternalId == "rpc-user@example.com")
        #expect(snapshot.accountIdentitySource == .email)
    }

    @Test
    func `probe falls back to account_id when no email in id_token`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let idToken = makeJWT(payload: ["sub": "user-sub-no-email"])
        try createAuthFile(at: tempDir, accountId: "acc-rpc-fallback", idToken: idToken)

        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 15, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexUsageProbe(client: mockClient, credentialLoader: loader)

        let snapshot = try await probe.probe()

        #expect(snapshot.accountExternalId == "acc-rpc-fallback")
        #expect(snapshot.accountIdentitySource == .external)
    }

    @Test
    func `probe has nil accountExternalId when no credentials`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 10, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexUsageProbe(client: mockClient, credentialLoader: loader)

        let snapshot = try await probe.probe()

        #expect(snapshot.accountExternalId == nil)
        #expect(snapshot.accountIdentitySource == nil)
    }
}

// MARK: - Mapping Tests

@Suite
struct CodexRateLimitsToSnapshotMappingTests {

    @Test
    func `maps primary window to session quota`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 40, resetDescription: "Resets in 1h"),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 60)
        #expect(snapshot.sessionQuota?.resetText == "Resets in 1h")
    }

    @Test
    func `maps secondary window to weekly quota`() throws {
        let response = CodexRateLimitsResponse(
            primary: nil,
            secondary: CodexRateLimitWindow(usedPercent: 20, resetDescription: "Resets in 5d")
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.weeklyQuota?.percentRemaining == 80)
        #expect(snapshot.weeklyQuota?.resetText == "Resets in 5d")
    }

    @Test
    func `maps both windows to quotas`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 30, resetDescription: nil),
            secondary: CodexRateLimitWindow(usedPercent: 60, resetDescription: nil)
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.sessionQuota?.percentRemaining == 70)
        #expect(snapshot.weeklyQuota?.percentRemaining == 40)
    }

    @Test
    func `throws when no rate limits found`() throws {
        let response = CodexRateLimitsResponse(primary: nil, secondary: nil)

        #expect(throws: ProbeError.self) {
            try CodexUsageProbe.mapRateLimitsToSnapshot(response)
        }
    }

    @Test
    func `sets provider id to codex`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 0, resetDescription: nil),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.providerId == "codex")
    }

    // MARK: - Account Identity Mapping Tests

    @Test
    func `mapRateLimitsToSnapshot passes through account identity from credentials`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 10, resetDescription: nil),
            secondary: nil
        )

        let credentials = CodexCredentialResult(
            accessToken: "token",
            accountId: "acc-mapped",
            fullData: [:]
        )

        let loader = CodexCredentialLoader()
        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response, credentials: credentials, credentialLoader: loader)

        #expect(snapshot.accountExternalId == "acc-mapped")
        #expect(snapshot.accountIdentitySource == .external)
    }

    @Test
    func `mapRateLimitsToSnapshot produces consistent fields with API mode`() throws {
        // This test verifies Step 5: API and RPC mode output consistent account fields.
        // Both modes use the same CodexCredentialLoader.resolveAccountIdentity method,
        // so given the same credentials, they produce identical accountExternalId and
        // accountIdentitySource values.
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 10, resetDescription: nil),
            secondary: nil
        )

        // Credentials with account_id only (no id_token)
        let credentials = CodexCredentialResult(
            accessToken: "token",
            accountId: "acc-consistent",
            fullData: [:]
        )

        let loader = CodexCredentialLoader()
        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response, credentials: credentials, credentialLoader: loader)

        // Both modes resolve through the same method
        let identity = loader.resolveAccountIdentity(credentials)
        #expect(snapshot.accountExternalId == identity?.externalId)
        #expect(snapshot.accountIdentitySource == identity?.source)
    }
}
