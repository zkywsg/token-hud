import Foundation

public enum DailyUsageAggregator {
    public struct DailySnapshot: Codable, Equatable, Sendable {
        public let date: String
        public var baseline: [String: ServiceSnapshot]
        public var latest: [String: ServiceSnapshot]
        public var services: [String: ServiceSnapshot] { latest }

        public init(
            date: String,
            baseline: [String: ServiceSnapshot] = [:],
            latest: [String: ServiceSnapshot] = [:]
        ) {
            self.date = date
            self.baseline = baseline
            self.latest = latest
        }

        private enum CodingKeys: String, CodingKey {
            case date, baseline, latest, services
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            if let latest = try container.decodeIfPresent([String: ServiceSnapshot].self, forKey: .latest) {
                self.latest = latest
                baseline = try container.decodeIfPresent([String: ServiceSnapshot].self, forKey: .baseline) ?? latest
            } else {
                let legacy = try container.decodeIfPresent([String: ServiceSnapshot].self, forKey: .services) ?? [:]
                baseline = legacy
                latest = legacy
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(date, forKey: .date)
            try container.encode(baseline, forKey: .baseline)
            try container.encode(latest, forKey: .latest)
        }
    }

    public struct ServiceSnapshot: Codable, Equatable, Sendable {
        public let tokens: Double?
        public let cost: Double?
        public let inputTokens: Double?
        public let outputTokens: Double?

        public init(
            tokens: Double? = nil,
            cost: Double? = nil,
            inputTokens: Double? = nil,
            outputTokens: Double? = nil
        ) {
            self.tokens = tokens
            self.cost = cost
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }

        var hasPositiveValue: Bool {
            [tokens, cost, inputTokens, outputTokens].contains { ($0 ?? 0) > 0 }
        }
    }

    public static func recordSnapshot(
        from stateFile: StateFile,
        existing snapshots: [DailySnapshot],
        date: String,
        cutoffDate: String? = nil
    ) -> [DailySnapshot] {
        let current = usageValues(from: stateFile)
        var next = snapshots
        if let index = next.firstIndex(where: { $0.date == date }) {
            var snapshot = next[index]
            for (id, value) in current where snapshot.baseline[id] == nil {
                snapshot.baseline[id] = value
            }
            snapshot.latest = current
            next[index] = snapshot
        } else {
            next.append(DailySnapshot(date: date, baseline: current, latest: current))
        }

        if let cutoffDate {
            next = prunedSnapshots(next, cutoffDate: cutoffDate)
        }
        return next
    }

    public static func deltaSnapshot(
        from snapshots: [DailySnapshot],
        date: String
    ) -> DailySnapshot? {
        guard let snapshot = snapshots.first(where: { $0.date == date }) else { return nil }
        var services: [String: ServiceSnapshot] = [:]
        for (id, latest) in snapshot.latest {
            guard let baseline = snapshot.baseline[id] else { continue }
            let delta = ServiceSnapshot(
                tokens: positiveDelta(latest.tokens, baseline.tokens),
                cost: positiveDelta(latest.cost, baseline.cost),
                inputTokens: positiveDelta(latest.inputTokens, baseline.inputTokens),
                outputTokens: positiveDelta(latest.outputTokens, baseline.outputTokens)
            )
            if delta.hasPositiveValue {
                services[id] = delta
            }
        }
        return DailySnapshot(date: snapshot.date, latest: services)
    }

    public static func prunedSnapshots(
        _ snapshots: [DailySnapshot],
        cutoffDate: String
    ) -> [DailySnapshot] {
        snapshots.filter { $0.date >= cutoffDate }
    }

    private static func usageValues(from stateFile: StateFile) -> [String: ServiceSnapshot] {
        var values: [String: ServiceSnapshot] = [:]
        for (id, service) in stateFile.services {
            if let snapshot = usageValue(from: service) {
                values[id] = snapshot
            }
        }
        return values
    }

    private static func usageValue(from service: Service) -> ServiceSnapshot? {
        let tokens = service.currentSession?.tokens
            ?? service.quotas.first(where: { $0.type == .tokens || $0.type == .dailyTokens || $0.type == .monthlyTokens })?.used
        let cost = service.currentSession?.costSpent
            ?? service.quotas.first(where: { $0.type == .costSpent })?.used
        let inputTokens = service.currentSession?.inputTokens
            ?? service.quotas.first(where: { $0.type == .inputTokens })?.used
        let outputTokens = service.currentSession?.outputTokens
            ?? service.quotas.first(where: { $0.type == .outputTokens })?.used
        let snapshot = ServiceSnapshot(
            tokens: tokens,
            cost: cost,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
        return snapshot.hasPositiveValue ? snapshot : nil
    }

    private static func positiveDelta(_ latest: Double?, _ baseline: Double?) -> Double? {
        guard let latest, let baseline else { return nil }
        let delta = latest - baseline
        return delta > 0 ? delta : nil
    }
}
