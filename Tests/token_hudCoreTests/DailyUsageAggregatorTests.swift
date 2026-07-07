import Testing
@testable import token_hudCore

@Suite("DailyUsageAggregator")
struct DailyUsageAggregatorTests {
    @Test func firstSnapshotCreatesBaselineWithoutDailyDelta() {
        let state = StateFile(
            version: 1,
            updatedAt: "2026-07-06T00:00:00Z",
            services: [
                "claude": Service(
                    label: "Claude",
                    quotas: [],
                    currentSession: SessionSnapshot(
                        id: "s1",
                        startedAt: "2026-07-06T00:00:00Z",
                        tokens: 1_000,
                        inputTokens: 600,
                        outputTokens: 400,
                        costSpent: 2
                    )
                )
            ]
        )

        let snapshots = DailyUsageAggregator.recordSnapshot(
            from: state,
            existing: [],
            date: "2026-07-06"
        )

        #expect(snapshots.count == 1)
        #expect(DailyUsageAggregator.deltaSnapshot(from: snapshots, date: "2026-07-06")?.services.isEmpty == true)
    }

    @Test func laterSnapshotReportsOnlyGrowthSinceBaseline() throws {
        let first = StateFile(
            version: 1,
            updatedAt: "2026-07-06T00:00:00Z",
            services: [
                "claude": Service(
                    label: "Claude",
                    quotas: [],
                    currentSession: SessionSnapshot(
                        id: "s1",
                        startedAt: "2026-07-06T00:00:00Z",
                        tokens: 1_000,
                        inputTokens: 600,
                        outputTokens: 400,
                        costSpent: 2
                    )
                ),
                "deepseek": Service(
                    label: "DeepSeek",
                    quotas: [Quota(type: .money, total: nil, used: 12, unit: "CNY", resetsAt: nil)],
                    currentSession: nil
                )
            ]
        )
        let second = StateFile(
            version: 1,
            updatedAt: "2026-07-06T01:00:00Z",
            services: [
                "claude": Service(
                    label: "Claude",
                    quotas: [],
                    currentSession: SessionSnapshot(
                        id: "s1",
                        startedAt: "2026-07-06T00:00:00Z",
                        tokens: 1_800,
                        inputTokens: 1_100,
                        outputTokens: 700,
                        costSpent: 3.5
                    )
                ),
                "deepseek": Service(
                    label: "DeepSeek",
                    quotas: [Quota(type: .money, total: nil, used: 15, unit: "CNY", resetsAt: nil)],
                    currentSession: nil
                )
            ]
        )

        let initial = DailyUsageAggregator.recordSnapshot(
            from: first,
            existing: [],
            date: "2026-07-06"
        )
        let updated = DailyUsageAggregator.recordSnapshot(
            from: second,
            existing: initial,
            date: "2026-07-06"
        )
        let delta = try #require(DailyUsageAggregator.deltaSnapshot(from: updated, date: "2026-07-06"))

        #expect(delta.services["claude"]?.tokens == 800)
        #expect(delta.services["claude"]?.inputTokens == 500)
        #expect(delta.services["claude"]?.outputTokens == 300)
        #expect(delta.services["claude"]?.cost == 1.5)
        #expect(delta.services["deepseek"] == nil)
    }

    @Test func keepsOnlyRecentSnapshots() {
        let old = DailyUsageAggregator.DailySnapshot(date: "2026-03-01")
        let current = DailyUsageAggregator.DailySnapshot(date: "2026-07-06")

        let pruned = DailyUsageAggregator.prunedSnapshots(
            [old, current],
            cutoffDate: "2026-04-07"
        )

        #expect(pruned.map(\.date) == ["2026-07-06"])
    }
}
