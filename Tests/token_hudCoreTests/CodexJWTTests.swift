// Tests/token_hudCoreTests/CodexJWTTests.swift
import Testing
import Foundation
@testable import token_hudCore

@Suite("CodexJWT")
struct CodexJWTTests {

    // Build a fake 3-part JWT with a known payload (signature ignored during decode).
    private func makeJWT(payload: [String: Any]) -> String {
        func b64url(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = b64url(Data("{\"alg\":\"RS256\",\"typ\":\"JWT\"}".utf8))
        let body   = b64url(try! JSONSerialization.data(withJSONObject: payload))
        return "\(header).\(body).fakesig"
    }

    // MARK: decodeJWTPayload

    @Test func decodesValidJWT() {
        let token = makeJWT(payload: ["sub": "user123", "exp": 9_999_999_999.0])
        let payload = decodeJWTPayload(token)
        #expect(payload != nil)
        #expect(payload?["sub"] as? String == "user123")
    }

    @Test func returnsNilForTwoPartToken() {
        #expect(decodeJWTPayload("header.payload") == nil)
    }

    @Test func returnsNilForNonBase64Payload() {
        #expect(decodeJWTPayload("h.!!!.s") == nil)
    }

    // MARK: isCodexTokenExpired

    @Test func freshTokenIsNotExpired() {
        let token = makeJWT(payload: ["exp": Date().timeIntervalSince1970 + 3600])
        #expect(isCodexTokenExpired(token: token) == false)
    }

    @Test func expiredTokenIsExpired() {
        let token = makeJWT(payload: ["exp": Date().timeIntervalSince1970 - 100])
        #expect(isCodexTokenExpired(token: token) == true)
    }

    @Test func tokenWithin60sBufferIsExpired() {
        // Expires 30 seconds from now — inside the 60s buffer
        let token = makeJWT(payload: ["exp": Date().timeIntervalSince1970 + 30])
        #expect(isCodexTokenExpired(token: token) == true)
    }

    @Test func tokenMissingExpIsExpired() {
        let token = makeJWT(payload: ["sub": "user"])
        #expect(isCodexTokenExpired(token: token) == true)
    }

    // MARK: buildCodexService

    @Test func buildServiceHasMoneyQuota() {
        let s = buildCodexService(costUsd: 5.0, costLimitUsd: 100.0, tokensUsed: 50_000, plan: "Pay-as-you-go")
        #expect(s.label == "Codex")
        #expect(s.error == nil)
        let money = s.quotas.first { $0.type == .money }
        #expect(money?.used == 5.0)
        #expect(money?.total == 100.0)
        #expect(money?.unit == "USD")
    }

    @Test func buildServiceStoresTokensInSession() {
        let s = buildCodexService(costUsd: 1.0, costLimitUsd: 50.0, tokensUsed: 12_345, plan: "Plus")
        #expect(s.currentSession?.tokens == 12_345.0)
    }

    // MARK: buildCodexErrorService

    @Test func errorServiceHasErrorField() {
        let s = buildCodexErrorService(error: "tokenExpired")
        #expect(s.error == "tokenExpired")
        #expect(s.quotas.isEmpty)
        #expect(s.currentSession == nil)
    }

    // MARK: mergeCodexService

    @Test func mergePreservesExistingServices() {
        let existing = StateFile(
            version: 1,
            updatedAt: "2026-04-01T00:00:00Z",
            services: ["claude": Service(label: "Claude", quotas: [], currentSession: nil)]
        )
        let merged = mergeCodexService(buildCodexErrorService(error: "notConfigured"), into: existing)
        #expect(merged.services["claude"] != nil)
        #expect(merged.services["codex"] != nil)
        #expect(merged.version == 1)
    }

    @Test func mergeIntoNilCreatesNewFile() {
        let merged = mergeCodexService(buildCodexErrorService(error: "notConfigured"), into: nil)
        #expect(merged.services.count == 1)
        #expect(merged.services["codex"] != nil)
        #expect(merged.version == 1)
    }
}
