// token_hud/State/DailySnapshotStore.swift
import Foundation

/// Stores daily usage snapshots for aggregation and trend display.
/// Each snapshot records the total tokens and cost per service for a given date.
struct DailySnapshotStore {
    private static let fileName = "daily-snapshots.json"

    typealias DailySnapshot = DailyUsageAggregator.DailySnapshot
    typealias ServiceSnapshot = DailyUsageAggregator.ServiceSnapshot

    /// Record a snapshot from the current state.json.
    static func recordSnapshot(from stateFile: StateFile) {
        let today = dateString(from: Date())
        let cutoff = dateString(from: Date().addingTimeInterval(-90 * 86400))
        let snapshots = DailyUsageAggregator.recordSnapshot(
            from: stateFile,
            existing: loadAll(),
            date: today,
            cutoffDate: cutoff
        )
        save(snapshots)
    }

    /// Load all stored snapshots.
    static func loadAll() -> [DailySnapshot] {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DailySnapshot].self, from: data)) ?? []
    }

    /// Get today's snapshot.
    static func todaySnapshot() -> DailySnapshot? {
        let today = dateString(from: Date())
        return DailyUsageAggregator.deltaSnapshot(from: loadAll(), date: today)
    }

    /// Get the last N days of snapshots.
    static func recentSnapshots(days: Int = 7) -> [DailySnapshot] {
        let cutoff = dateString(from: Date().addingTimeInterval(-Double(days * 86400)))
        return loadAll().filter { $0.date >= cutoff }
    }

    // MARK: - Private

    private static func storageURL() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".token-hud")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private static func save(_ snapshots: [DailySnapshot]) {
        let url = storageURL()
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
