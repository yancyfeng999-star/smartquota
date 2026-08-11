import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("CodexCredentialLoader Tests")
struct CodexCredentialLoaderTests {

    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-credential-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createAuthFile(
        at directory: URL,
        accessToken: String = "test-access-token",
        refreshToken: String = "test-refresh-token",
        accountId: String? = nil,
        lastRefresh: String? = nil,
        apiKey: String? = nil,
        idToken: String? = nil
    ) throws {
        let codexDir = directory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        var tokens: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken
        ]
        if let accountId {
            tokens["account_id"] = accountId
        }
        if let idToken {
            tokens["id_token"] = idToken
        }

        var auth: [String: Any] = [
            "tokens": tokens
        ]
        if let lastRefresh {
            auth["last_refresh"] = lastRefresh
        }
        if let apiKey {
            auth["OPENAI_API_KEY"] = apiKey
        }

        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
        let filePath = codexDir.appendingPathComponent("auth.json")
        try data.write(to: filePath)
    }

    // MARK: - JWT Helpers

    /// Creates a minimal JWT with the given payload claims.
    /// Uses a dummy header and empty signature for testing.
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

    // MARK: - Credential Loading Tests

    @Test
    func `loadCredentials returns nil when file does not exist`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials returns credentials from file`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(
            at: tempDir,
            accessToken: "my-access-token",
            refreshToken: "my-refresh-token",
            accountId: "acc-123"
        )

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(result?.accessToken == "my-access-token")
        #expect(result?.refreshToken == "my-refresh-token")
        #expect(result?.accountId == "acc-123")
    }

    @Test
    func `loadCredentials returns nil when access token is empty`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, accessToken: "")

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials handles malformed JSON gracefully`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let codexDir = tempDir.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let filePath = codexDir.appendingPathComponent("auth.json")
        try "not valid json".write(to: filePath, atomically: true, encoding: .utf8)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials handles missing tokens field`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let codexDir = tempDir.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let filePath = codexDir.appendingPathComponent("auth.json")
        let data = try JSONSerialization.data(withJSONObject: ["someOtherKey": "value"], options: [])
        try data.write(to: filePath)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials detects API key auth`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let codexDir = tempDir.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let filePath = codexDir.appendingPathComponent("auth.json")
        let auth: [String: Any] = ["OPENAI_API_KEY": "sk-test-key"]
        let data = try JSONSerialization.data(withJSONObject: auth, options: [])
        try data.write(to: filePath)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        // API key auth should return nil (not usable for usage API)
        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials loads id_token from file`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let idToken = makeJWT(payload: ["email": "user@example.com", "sub": "user-123"])
        try createAuthFile(at: tempDir, idToken: idToken)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(result?.idToken == idToken)
    }

    // MARK: - Token Refresh Need Tests

    @Test
    func `needsRefresh returns true when lastRefresh is nil`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, lastRefresh: nil)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(lastRefresh: result?.lastRefresh) == true)
    }

    @Test
    func `needsRefresh returns true when lastRefresh is older than 8 days`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 9 days ago
        let oldDate = Date().addingTimeInterval(-9 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let oldDateStr = formatter.string(from: oldDate)

        try createAuthFile(at: tempDir, lastRefresh: oldDateStr)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(lastRefresh: result?.lastRefresh) == true)
    }

    @Test
    func `needsRefresh returns false when lastRefresh is recent`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1 day ago
        let recentDate = Date().addingTimeInterval(-1 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recentDateStr = formatter.string(from: recentDate)

        try createAuthFile(at: tempDir, lastRefresh: recentDateStr)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(lastRefresh: result?.lastRefresh) == false)
    }

    // MARK: - Credential Saving Tests

    @Test
    func `saveCredentials updates file correctly`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(
            at: tempDir,
            accessToken: "old-token",
            refreshToken: "old-refresh"
        )

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        var result = loader.loadCredentials()!

        // Update the tokens
        result.accessToken = "new-token"
        result.refreshToken = "new-refresh"
        result.lastRefresh = ISO8601DateFormatter().string(from: Date())

        loader.saveCredentials(result)

        // Reload and verify
        let reloaded = loader.loadCredentials()
        #expect(reloaded?.accessToken == "new-token")
        #expect(reloaded?.refreshToken == "new-refresh")
        #expect(reloaded?.lastRefresh != nil)
    }

    // MARK: - JWT Email Extraction Tests

    @Test
    func `extractEmailFromJWT returns email from valid id_token`() throws {
        let idToken = makeJWT(payload: [
            "email": "user@example.com",
            "sub": "user-sub-123",
            "iss": "https://auth.openai.com"
        ])

        let email = CodexCredentialLoader.extractEmailFromJWT(idToken)

        #expect(email == "user@example.com")
    }

    @Test
    func `extractEmailFromJWT returns nil for malformed JWT`() throws {
        // Not enough parts (no dots)
        #expect(CodexCredentialLoader.extractEmailFromJWT("not-a-jwt") == nil)

        // Only one part
        #expect(CodexCredentialLoader.extractEmailFromJWT("singlepart") == nil)

        // Empty string
        #expect(CodexCredentialLoader.extractEmailFromJWT("") == nil)
    }

    @Test
    func `extractEmailFromJWT returns nil when payload is not valid base64`() throws {
        let malformed = "header.!!!not-base64!!!.sig"
        #expect(CodexCredentialLoader.extractEmailFromJWT(malformed) == nil)
    }

    @Test
    func `extractEmailFromJWT returns nil when email claim is missing`() throws {
        // JWT with sub but no email
        let idToken = makeJWT(payload: [
            "sub": "user-sub-123",
            "iss": "https://auth.openai.com"
        ])

        let email = CodexCredentialLoader.extractEmailFromJWT(idToken)

        #expect(email == nil)
    }

    @Test
    func `extractEmailFromJWT does not extract sub claim`() throws {
        // Verify we only extract email, not sub (which is a stable cross-service ID)
        let idToken = makeJWT(payload: [
            "sub": "user-sub-123",
            "email": "user@example.com"
        ])

        // We can only verify email is returned; sub is deliberately not exposed
        let email = CodexCredentialLoader.extractEmailFromJWT(idToken)
        #expect(email == "user@example.com")
    }

    // MARK: - Account Identity Resolution Tests

    @Test
    func `resolveAccountIdentity returns email from id_token when available`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let idToken = makeJWT(payload: ["email": "user@example.com"])
        try createAuthFile(at: tempDir, accountId: "acc-456", idToken: idToken)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()!
        let identity = loader.resolveAccountIdentity(credentials)

        #expect(identity != nil)
        #expect(identity?.externalId == "user@example.com")
        #expect(identity?.source == .email)
    }

    @Test
    func `resolveAccountIdentity falls back to account_id when id_token has no email`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // id_token with sub but no email
        let idToken = makeJWT(payload: ["sub": "user-sub-123"])
        try createAuthFile(at: tempDir, accountId: "acc-456", idToken: idToken)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()!
        let identity = loader.resolveAccountIdentity(credentials)

        #expect(identity != nil)
        #expect(identity?.externalId == "acc-456")
        #expect(identity?.source == .external)
    }

    @Test
    func `resolveAccountIdentity falls back to account_id when no id_token`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, accountId: "acc-789")

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()!
        let identity = loader.resolveAccountIdentity(credentials)

        #expect(identity != nil)
        #expect(identity?.externalId == "acc-789")
        #expect(identity?.source == .external)
    }

    @Test
    func `resolveAccountIdentity returns nil when no identity available`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir) // no accountId, no idToken

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()!
        let identity = loader.resolveAccountIdentity(credentials)

        #expect(identity == nil)
    }

    // MARK: - Two Fake Account Fixtures

    @Test
    func `resolveAccountIdentity distinguishes two different accounts`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Account A: has email in id_token
        let idTokenA = makeJWT(payload: ["email": "alice@company.com"])
        let codexDir = tempDir.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let authA: [String: Any] = [
            "tokens": [
                "access_token": "token-a",
                "refresh_token": "refresh-a",
                "account_id": "acc-alice",
                "id_token": idTokenA
            ] as [String: Any]
        ]
        let dataA = try JSONSerialization.data(withJSONObject: authA, options: [.prettyPrinted])
        try dataA.write(to: codexDir.appendingPathComponent("auth.json"))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credsA = loader.loadCredentials()!
        let identityA = loader.resolveAccountIdentity(credsA)

        #expect(identityA?.externalId == "alice@company.com")
        #expect(identityA?.source == .email)

        // Account B: no email, only account_id
        let authB: [String: Any] = [
            "tokens": [
                "access_token": "token-b",
                "refresh_token": "refresh-b",
                "account_id": "acc-bob"
            ] as [String: Any]
        ]
        let dataB = try JSONSerialization.data(withJSONObject: authB, options: [.prettyPrinted])
        try dataB.write(to: codexDir.appendingPathComponent("auth.json"))

        let credsB = loader.loadCredentials()!
        let identityB = loader.resolveAccountIdentity(credsB)

        #expect(identityB?.externalId == "acc-bob")
        #expect(identityB?.source == .external)

        // They should be different
        #expect(identityA?.externalId != identityB?.externalId)
    }
}
