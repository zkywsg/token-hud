// Sources/token_hudCore/UsageHistory.swift
import Foundation

/// One observation of a provider's *cumulative* usage counter.
public struct UsageSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cumulative: Double

    public init(timestamp: Date, cumulative: Double) {
        self.timestamp = timestamp
        self.cumulative = cumulative
    }
}

/// Usage attributed to a single calendar day.
public struct DailyUsage: Equatable, Sendable, Identifiable {
    public let day: Date
    public let amount: Double

    public var id: Date { day }

    public init(day: Date, amount: Double) {
        self.day = day
        self.amount = amount
    }
}

/// Turns a series of cumulative readings into per-day consumption.
///
/// Providers only report "used so far this cycle", so daily figures have to be
/// derived by differencing consecutive samples. Two realities shape this:
///
/// - **Cycle resets** drop the counter back toward zero. A negative difference
///   therefore means "new cycle", and the consumption for that interval is the
///   new reading itself — not a negative number.
/// - **Gaps** (the app wasn't running) can't be reconstructed. The whole
///   difference lands on the day of the later sample, which inflates that day.
///   That's reported as-is rather than smeared, so the numbers stay traceable.
public enum UsageHistoryCalculator {

    /// Minimum spacing between stored samples; polling is far more frequent
    /// than this and every sample would otherwise be kept.
    public static let minimumSampleInterval: TimeInterval = 300

    /// How much history is worth keeping.
    public static let retentionDays = 30

    /// A chart appears as soon as a single day has real consumption. Waiting for
    /// three made the whole feature invisible for days after install, with no
    /// sign it was working; one day plus zero-bars for the rest reads correctly
    /// and gives immediate feedback.
    public static let minimumDaysForChart = 1

    /// Per-day consumption derived from cumulative samples, oldest first.
    /// Days inside the range with no consumption are returned as zero so the
    /// chart keeps a stable number of bars.
    public static func dailyUsage(
        from samples: [UsageSample],
        days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyUsage] {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        var totals: [Date: Double] = [:]

        for (index, sample) in ordered.enumerated() where index > 0 {
            let previous = ordered[index - 1]
            let delta = sample.cumulative - previous.cumulative
            // A drop means the cycle rolled over; everything on the new counter
            // was consumed during this interval.
            let consumed = delta >= 0 ? delta : sample.cumulative
            guard consumed > 0 else { continue }
            let day = calendar.startOfDay(for: sample.timestamp)
            totals[day, default: 0] += consumed
        }

        let today = calendar.startOfDay(for: now)
        return (0..<max(1, days)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyUsage(day: day, amount: totals[day] ?? 0)
        }
    }

    /// Number of days that actually recorded consumption — used to decide
    /// whether there's enough history to chart.
    public static func recordedDayCount(
        from samples: [UsageSample],
        calendar: Calendar = .current
    ) -> Int {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        var days = Set<Date>()
        for (index, sample) in ordered.enumerated() where index > 0 {
            let delta = sample.cumulative - ordered[index - 1].cumulative
            let consumed = delta >= 0 ? delta : sample.cumulative
            if consumed > 0 { days.insert(calendar.startOfDay(for: sample.timestamp)) }
        }
        return days.count
    }

    /// Drops samples older than `retentionDays`, and samples closer together
    /// than `minimumSampleInterval` (keeping the newest of each cluster).
    public static func pruned(
        _ samples: [UsageSample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [UsageSample] {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) else { return samples }
        let recent = samples.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }

        var thinned: [UsageSample] = []
        for sample in recent {
            if let last = thinned.last,
               sample.timestamp.timeIntervalSince(last.timestamp) < minimumSampleInterval {
                // Keep the newer reading for this slot so the latest cumulative
                // value is never stale.
                thinned[thinned.count - 1] = sample
            } else {
                thinned.append(sample)
            }
        }
        return thinned
    }

    /// Projected consumption for a whole cycle, from how far through it we are.
    /// Returns nil when the cycle position is unknown or too early to be useful.
    public static func projectedCycleTotal(used: Double, cycleElapsedFraction: Double) -> Double? {
        guard cycleElapsedFraction > 0.02, cycleElapsedFraction <= 1, used > 0 else { return nil }
        return used / cycleElapsedFraction
    }
}
