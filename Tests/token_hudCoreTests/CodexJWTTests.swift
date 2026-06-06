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

    @Test func codexAuthClaimReadsCurrentOpenAIAuthNamespace() {
        let payload: [String: Any] = [
            "email": "user@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": "plus"
            ],
        ]

        let claim = codexAuthClaim(from: payload)

        #expect(claim.email == "user@example.com")
        #expect(claim.plan == "plus")
    }

    @Test func codexAuthClaimFallsBackToLegacyAuthNamespace() {
        let payload: [String: Any] = [
            "email": "user@example.com",
            "auth": [
                "chatgpt_plan_type": "team"
            ],
        ]

        #expect(codexAuthClaim(from: payload).plan == "team")
    }

    @Test func codexWhamUsageParserBuildsPlanAndRateLimitQuotas() throws {
        let json = """
        {
          "email": "user@example.com",
          "plan_type": "plus",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": 25,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 15084,
              "reset_at": 1780785631
            },
            "secondary_window": {
              "used_percent": 40,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 369726,
              "reset_at": 1781140273
            }
          },
          "credits": {
            "has_credits": true,
            "balance": "12.5"
          }
        }
        """

        let service = try #require(CodexWhamUsageParser.service(from: Data(json.utf8)))

        #expect(service.label == "Codex Plus")
        #expect(service.error == nil)
        #expect(service.quotas.count == 3)

        let primary = try #require(service.quotas.first { $0.type == .time && $0.total == 18_000 })
        #expect(primary.used == 4_500)
        #expect(primary.unit == "seconds")
        #expect(primary.resetsAt != nil)

        let secondary = try #require(service.quotas.first { $0.type == .time && $0.total == 604_800 })
        #expect(secondary.used == 241_920)

        let credits = try #require(service.quotas.first { $0.unit == "credits" })
        #expect(credits.used == 12.5)
    }

    // MARK: buildCodexService

    @Test func buildServiceHasMoneyQuota() {
        let s = buildCodexService(costUsd: 5.0, costLimitUsd: 100.0, tokensUsed: 50_000)
        #expect(s.label == "Codex")
        #expect(s.error == nil)
        let money = s.quotas.first { $0.type == .money }
        #expect(money?.used == 5.0)
        #expect(money?.total == 100.0)
        #expect(money?.unit == "USD")
    }

    @Test func buildServiceStoresTokensInSession() {
        // Use a known date: April 5, 2026 → first of month = April 1, 2026
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 5
        let knownDate = Calendar.current.date(from: comps)!
        let s = buildCodexService(costUsd: 1.0, costLimitUsd: 50.0, tokensUsed: 12_345, now: knownDate)
        #expect(s.currentSession?.tokens == 12_345.0)
        // startedAt should be first of the month
        var firstComps = DateComponents()
        firstComps.year = 2026; firstComps.month = 4; firstComps.day = 1
        let firstOfMonth = Calendar.current.date(from: firstComps)!
        #expect(s.currentSession?.startedAt == ISO8601DateFormatter().string(from: firstOfMonth))
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
        let merged = mergeCodexService(buildCodexErrorService(error: "notConfigured"), into: existing, now: Date())
        #expect(merged.services["claude"] != nil)
        #expect(merged.services["codex"] != nil)
        #expect(merged.version == 1)
    }

    @Test func mergeIntoNilCreatesNewFile() {
        let merged = mergeCodexService(buildCodexErrorService(error: "notConfigured"), into: nil, now: Date())
        #expect(merged.services.count == 1)
        #expect(merged.services["codex"] != nil)
        #expect(merged.version == 1)
    }
}
