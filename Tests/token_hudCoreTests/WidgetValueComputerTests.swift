import Foundation
import Testing
@testable import token_hudCore

@Suite("WidgetValueComputer")
struct WidgetValueComputerTests {

    let timeQuota  = Quota(type: .time,   total: 18000,     used: 9000,    unit: "seconds", resetsAt: nil)
    let moneyQuota = Quota(type: .money,  total: 20.0,      used: 1.5,     unit: "USD",     resetsAt: nil)
    let tokenQuota = Quota(type: .tokens, total: 1_000_000, used: 150_000, unit: "tokens",  resetsAt: nil)

    @Test func remainingTimeValue() {
        #expect(WidgetValueComputer.remainingValue(for: timeQuota) == 9000)
    }

    @Test func usageFraction() {
        #expect(WidgetValueComputer.usageFraction(for: timeQuota) == 0.5)
    }

    @Test func formattedRemainingTime() {
        #expect(WidgetValueComputer.formattedRemaining(quota: timeQuota) == "2h 30m")
    }

    @Test func formattedRemainingMoney() {
        #expect(WidgetValueComputer.formattedRemaining(quota: moneyQuota) == "$18.50")
    }

    @Test func formattedRemainingTokens() {
        #expect(WidgetValueComputer.formattedRemaining(quota: tokenQuota) == "850k")
    }

    @Test func sessionTokensFormatted() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z",
                                      tokens: 1500, time: nil, money: nil, requests: nil)
        #expect(WidgetValueComputer.formattedSessionTokens(session) == "1.5k")
    }

    // MARK: - New QuotaType formatting

    @Test func formattedRemainingInputTokens() {
        let q = Quota(type: .inputTokens, total: 100_000, used: 35_000, unit: "tokens", resetsAt: nil)
        #expect(WidgetValueComputer.formattedRemaining(quota: q) == "65k")
    }

    @Test func formattedRemainingCostSpent() {
        let q = Quota(type: .costSpent, total: 50.0, used: 12.35, unit: "USD", resetsAt: nil)
        #expect(WidgetValueComputer.formattedRemaining(quota: q) == "$37.65")
    }

    @Test func formattedRemainingDailyRequests() {
        let q = Quota(type: .dailyRequests, total: 1000, used: 420, unit: "requests", resetsAt: nil)
        #expect(WidgetValueComputer.formattedRemaining(quota: q) == "580")
    }

    @Test func formattedUsedInputTokensNoCap() {
        let q = Quota(type: .inputTokens, total: nil, used: 250_000, unit: "tokens", resetsAt: nil)
        #expect(WidgetValueComputer.formattedRemaining(quota: q) == "250k")
    }

    // MARK: - Session snapshot formatting

    @Test func formattedInputTokens() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z",
                                      inputTokens: 8200)
        #expect(WidgetValueComputer.formattedInputTokens(session) == "8.2k")
    }

    @Test func formattedInputTokensNil() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z")
        #expect(WidgetValueComputer.formattedInputTokens(session) == "—")
    }

    @Test func formattedOutputTokens() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z",
                                      outputTokens: 4300)
        #expect(WidgetValueComputer.formattedOutputTokens(session) == "4.3k")
    }

    @Test func formattedCostSpent() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z",
                                      costSpent: 12.35)
        #expect(WidgetValueComputer.formattedCostSpent(session) == "$12.35")
    }

    @Test func formattedCostSpentNil() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z")
        #expect(WidgetValueComputer.formattedCostSpent(session) == "—")
    }

    // MARK: - Derived metrics

    @Test func sessionDurationFormatting() {
        let session = SessionSnapshot(id: "x", startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -8100))) // 2h 15m ago
        let result = WidgetValueComputer.sessionDuration(from: session)
        // Should contain "2h" (might vary by a second)
        #expect(result.contains("2h"))
    }

    @Test func tokensPerMinuteFormatting() {
        let session = SessionSnapshot(id: "x", startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -6000)), tokens: 15000)
        let result = WidgetValueComputer.tokensPerMinute(from: session)
        // 15000 / 100min = 150/min
        #expect(result == "150/min")
    }

    @Test func inputOutputRatioFormatting() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z", inputTokens: 7500, outputTokens: 3000)
        #expect(WidgetValueComputer.inputOutputRatio(from: session) == "2.5:1")
    }

    @Test func inputOutputRatioNil() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z")
        #expect(WidgetValueComputer.inputOutputRatio(from: session) == "—")
    }

    @Test func costPerRequestFormatting() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z", requests: 5, costSpent: 1.40)
        #expect(WidgetValueComputer.costPerRequest(from: session) == "$0.28")
    }

    @Test func costPerRequestNil() {
        let session = SessionSnapshot(id: "x", startedAt: "2026-04-01T00:00:00Z")
        #expect(WidgetValueComputer.costPerRequest(from: session) == "—")
    }

    @Test func formattedModelTokensTest() {
        let usage = ModelUsage(model: "test", inputTokens: 30000, outputTokens: 15000)
        #expect(WidgetValueComputer.formattedModelTokens(usage) == "45k")
    }

    @Test func formattedModelCostTest() {
        let usage = ModelUsage(model: "test", costSpent: 0.85)
        #expect(WidgetValueComputer.formattedModelCost(usage) == "$0.85")
    }

    @Test func formattedModelCostNil() {
        let usage = ModelUsage(model: "test")
        #expect(WidgetValueComputer.formattedModelCost(usage) == "—")
    }
}
