// Tests/token_hudCoreTests/UsageHistoryTests.swift
import Foundation
import Testing
@testable import token_hudCore

@Suite("Usage history")
struct UsageHistoryTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        DateComponents(
            calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026, month: 8, day: day, hour: hour
        ).date!
    }

    @Test("Consecutive readings difference into daily consumption")
    func dailyDeltas() {
        let samples = [
            UsageSample(timestamp: date(1, 9), cumulative: 100),
            UsageSample(timestamp: date(1, 18), cumulative: 300),  // +200 on the 1st
            UsageSample(timestamp: date(2, 9), cumulative: 500),   // +200 on the 2nd
            UsageSample(timestamp: date(3, 9), cumulative: 900),   // +400 on the 3rd
        ]
        let daily = UsageHistoryCalculator.dailyUsage(
            from: samples, days: 3, now: date(3, 20), calendar: calendar
        )
        #expect(daily.map(\.amount) == [200, 200, 400])
    }

    @Test("A drop is a cycle reset, not negative usage")
    func cycleResetCountsFromZero() {
        let samples = [
            UsageSample(timestamp: date(1, 9), cumulative: 900),
            UsageSample(timestamp: date(2, 9), cumulative: 120),  // reset; 120 consumed
        ]
        let daily = UsageHistoryCalculator.dailyUsage(
            from: samples, days: 2, now: date(2, 20), calendar: calendar
        )
        #expect(daily.map(\.amount) == [0, 120])
        #expect(daily.allSatisfy { $0.amount >= 0 })
    }

    @Test("Days without consumption still produce zero bars")
    func missingDaysAreZero() {
        let samples = [
            UsageSample(timestamp: date(1, 9), cumulative: 100),
            UsageSample(timestamp: date(3, 9), cumulative: 300),
        ]
        let daily = UsageHistoryCalculator.dailyUsage(
            from: samples, days: 3, now: date(3, 20), calendar: calendar
        )
        #expect(daily.count == 3)
        #expect(daily.map(\.amount) == [0, 0, 200]) // gap lands on the later day
    }

    @Test("Recorded day count drives the chart threshold")
    func recordedDays() {
        let samples = [
            UsageSample(timestamp: date(1, 9), cumulative: 10),
            UsageSample(timestamp: date(2, 9), cumulative: 20),
            UsageSample(timestamp: date(3, 9), cumulative: 30),
        ]
        #expect(UsageHistoryCalculator.recordedDayCount(from: samples, calendar: calendar) == 2)
        #expect(UsageHistoryCalculator.minimumDaysForChart == 1)
    }

    @Test("Pruning drops old samples and thins dense ones")
    func pruning() {
        let now = date(20)
        let old = UsageSample(timestamp: date(20).addingTimeInterval(-40 * 86400), cumulative: 1)
        let a = UsageSample(timestamp: now.addingTimeInterval(-600), cumulative: 10)
        let b = UsageSample(timestamp: now.addingTimeInterval(-590), cumulative: 11) // 10s later
        let c = UsageSample(timestamp: now, cumulative: 20)
        let kept = UsageHistoryCalculator.pruned([old, a, b, c], now: now, calendar: calendar)
        #expect(!kept.contains(old))
        #expect(kept.count == 2)          // a and b collapse into one slot
        #expect(kept.first?.cumulative == 11) // newest reading of the cluster wins
    }

    @Test("Projection needs a meaningful slice of the cycle")
    func projection() {
        #expect(UsageHistoryCalculator.projectedCycleTotal(used: 100, cycleElapsedFraction: 0.5) == 200)
        #expect(UsageHistoryCalculator.projectedCycleTotal(used: 100, cycleElapsedFraction: 0.01) == nil)
        #expect(UsageHistoryCalculator.projectedCycleTotal(used: 0, cycleElapsedFraction: 0.5) == nil)
    }
}
