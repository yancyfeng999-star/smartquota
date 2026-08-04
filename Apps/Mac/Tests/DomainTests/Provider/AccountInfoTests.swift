import Testing
@testable import Domain

@Suite
struct AccountInfoTests {

    @Test
    func `displays email as primary display name`() {
        let info = AccountInfo(email: "user@example.com", organization: "Acme Corp")

        #expect(info.displayName == "user@example.com")
    }

    @Test
    func `falls back to organization when email is nil`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(info.displayName == "Acme Corp")
    }

    @Test
    func `displayName is nil when both are nil`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.displayName == nil)
    }

    @Test
    func `isEmpty when no fields are populated`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.isEmpty)
    }

    @Test
    func `is not empty when email is present`() {
        let info = AccountInfo(email: "user@example.com", organization: nil)

        #expect(!info.isEmpty)
    }

    @Test
    func `is not empty when organization is present`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(!info.isEmpty)
    }

    @Test
    func `initial letter from email`() {
        let info = AccountInfo(email: "user@example.com", organization: nil)

        #expect(info.initialLetter == "U")
    }

    @Test
    func `initial letter from organization when no email`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(info.initialLetter == "A")
    }

    @Test
    func `initial letter is nil when empty`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.initialLetter == nil)
    }

    @Test
    func `preserves login method`() {
        let info = AccountInfo(email: "user@example.com", organization: nil, loginMethod: "Claude Max")

        #expect(info.loginMethod == "Claude Max")
    }

    @Test
    func `equatable conformance`() {
        let a = AccountInfo(email: "user@example.com", organization: "Org")
        let b = AccountInfo(email: "user@example.com", organization: "Org")

        #expect(a == b)
    }
}
