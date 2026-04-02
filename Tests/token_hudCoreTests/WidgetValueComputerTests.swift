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
}
