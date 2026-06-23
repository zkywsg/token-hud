import Testing
@testable import token_hudCore

@Suite("Keychain access policy")
struct KeychainAccessPolicyTests {
    @Test func statusChecksNeverAllowUserInteraction() {
        #expect(!KeychainAccessPolicy.allowsUserInteraction(for: .statusCheck))
    }

    @Test func secretReadsFollowExplicitInteractionFlag() {
        #expect(!KeychainAccessPolicy.allowsUserInteraction(for: .secretRead(allowUserInteraction: false)))
        #expect(KeychainAccessPolicy.allowsUserInteraction(for: .secretRead(allowUserInteraction: true)))
    }
}
