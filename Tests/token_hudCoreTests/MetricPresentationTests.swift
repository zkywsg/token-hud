// Tests/token_hudCoreTests/MetricPresentationTests.swift
import Testing
@testable import token_hudCore

@Suite("Metric presentation")
struct MetricPresentationTests {
    @Test("Only quota presentation exposes a fraction and a gauge")
    func quotaExposesFraction() {
        #expect(MetricPresentation.quota(0.42).fraction == 0.42)
        #expect(MetricPresentation.quota(0.42).showsGauge)
        #expect(MetricPresentation.counter.fraction == nil)
        #expect(!MetricPresentation.counter.showsGauge)
        #expect(MetricPresentation.status.fraction == nil)
        #expect(!MetricPresentation.status.showsGauge)
    }

    @Test("Retired metrics cover the duplicated and invented-denominator sets")
    func retiredSet() {
        for raw in ["subscription_status", "plan_name", "reset_countdown",
                    "session_duration", "tokens_per_minute",
                    "input_output_ratio", "cost_per_request"] {
            #expect(RetiredMetrics.isRetired(raw), "\(raw) should be retired")
        }
    }

    @Test("Metrics that still carry meaning are not retired")
    func keptMetrics() {
        for raw in ["remaining_time", "tokens_remaining", "balance", "session_tokens",
                    "usage_percent", "input_tokens", "output_tokens", "daily_tokens",
                    "monthly_tokens", "cost_spent", "daily_requests", "monthly_requests",
                    "rate_limit_status", "credits_remaining", "credits_used", "session_credits"] {
            #expect(!RetiredMetrics.isRetired(raw), "\(raw) should be kept")
        }
    }

    @Test("Sixteen metrics survive the cut")
    func survivingCount() {
        #expect(RetiredMetrics.rawValues.count == 7)
    }
}
