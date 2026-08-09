// token_hud/State/UsageHistoryStore.swift
import Foundation
import Observation

/// Records each provider's cumulative usage over time so per-day consumption
/// can be derived. Providers only report "used so far this cycle", so without
/// this local log there is no way to know what a given day cost.
///
/// Stored next to the state file (`~/.token-hud/usage-history.json`) rather than
/// in UserDefaults, since it grows with time and is plain diagnostic data.
@Observable
@MainActor
final class UsageHistoryStore {

    /// Samples keyed by `service:metricKind` (e.g. `codex:tokens`).
    private(set) var samples: [String: [UsageSample]] = [:]

    private let fileURL: URL
    private var lastWrite = Date.distantPast

    /// Providers whose counter climbs within a cycle and resets. DeepSeek is
    /// deliberately absent: its `used` field actually carries the remaining
    /// balance, which falls as you spend and jumps on top-up, so differencing
    /// it here would read every day as a cycle reset.
    static let trackedServices: Set<String> = ["codex", "mimo", "claude"]

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".token-hud", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("usage-history.json")
        load()
    }

    // MARK: - Recording

    /// Appends a reading for every tracked provider in `state`. Cheap enough to
    /// call on every state refresh — `pruned` throttles what actually persists.
    func record(from state: StateFile?, now: Date = Date()) {
        guard let state else { return }
        var changed = false

        for (serviceID, service) in state.services where Self.trackedServices.contains(serviceID) {
            guard service.error == nil else { continue }
            guard let quota = Self.trackedQuota(of: service) else { continue }
            let key = "\(serviceID):\(quota.type.rawValue)"
            var series = samples[key] ?? []
            series.append(UsageSample(timestamp: now, cumulative: quota.used))
            let cleaned = UsageHistoryCalculator.pruned(series, now: now)
            if cleaned != samples[key] {
                samples[key] = cleaned
                changed = true
            }
        }

        // Writing on every poll would be wasteful; the in-memory series is
        // already current for the UI.
        if changed, now.timeIntervalSince(lastWrite) >= UsageHistoryCalculator.minimumSampleInterval {
            lastWrite = now
            save()
        }
    }

    /// The quota that represents "usage this cycle" for a provider. Prefers a
    /// capped quota (so the chart can also show headroom) and otherwise takes
    /// the first token-like counter.
    private static func trackedQuota(of service: Service) -> Quota? {
        if let capped = service.quotas.first(where: { $0.total != nil && ($0.total ?? 0) > 0 && $0.type != .time }) {
            return capped
        }
        return service.quotas.first { $0.type == .tokens || $0.type == .monthlyTokens || $0.type == .dailyTokens }
    }

    // MARK: - Reading

    func series(for serviceID: String) -> [UsageSample] {
        samples.first { $0.key.hasPrefix("\(serviceID):") }?.value ?? []
    }

    func dailyUsage(for serviceID: String, days: Int, now: Date = Date()) -> [DailyUsage] {
        UsageHistoryCalculator.dailyUsage(from: series(for: serviceID), days: days, now: now)
    }

    /// Whether there's enough history for a bar chart to say anything.
    func hasChartableHistory(for serviceID: String) -> Bool {
        UsageHistoryCalculator.recordedDayCount(from: series(for: serviceID))
            >= UsageHistoryCalculator.minimumDaysForChart
    }

    func recordedDayCount(for serviceID: String) -> Int {
        UsageHistoryCalculator.recordedDayCount(from: series(for: serviceID))
    }

    /// Calendar days spanned since recording began. Distinct from
    /// `recordedDayCount`, which only counts days that saw consumption — an
    /// idle day still counts as "recording", and the UI needs to say so.
    func daysSinceFirstSample(for serviceID: String, now: Date = Date()) -> Int? {
        guard let first = series(for: serviceID).first?.timestamp else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: first),
            to: cal.startOfDay(for: now)
        ).day ?? 0
        return max(0, days) + 1
    }

    /// Services currently being sampled, ordered for stable display.
    var trackedServiceIDs: [String] {
        samples.keys
            .compactMap { $0.split(separator: ":").first.map(String.init) }
            .reduce(into: [String]()) { acc, id in if !acc.contains(id) { acc.append(id) } }
            .sorted()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        samples = (try? decoder.decode([String: [UsageSample]].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(samples) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
