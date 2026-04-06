// token_hud/State/CodexFetcher.swift
import Foundation
import Observation
import SQLite3

/// Reads Codex usage data from the local ~/.codex/state_5.sqlite database
/// and writes it into ~/.token-hud/state.json under the "codex" key.
///
/// No network requests are made — all data comes from Codex's own SQLite store.
/// Lifecycle: init → starts timer + fires immediately. Call stop() before discarding.
@Observable
@MainActor
final class CodexFetcher {

    private(set) var isFetching = false

    private var timer: Timer?
    private var currentInterval: Int = 0
    private var defaultsObserver: NSObjectProtocol?
    private var initialFetchTask: Task<Void, Never>?

    init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rescheduleIfNeeded() }
        }
        rescheduleIfNeeded()
        initialFetchTask = Task { await fetch() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        initialFetchTask?.cancel()
        initialFetchTask = nil
        if let obs = defaultsObserver {
            NotificationCenter.default.removeObserver(obs)
            defaultsObserver = nil
        }
    }

    // MARK: - Timer

    private var refreshInterval: Int {
        let v = UserDefaults.standard.integer(forKey: "refreshInterval")
        return v > 0 ? v : 300
    }

    private func rescheduleIfNeeded() {
        let newInterval = refreshInterval
        guard newInterval != currentInterval else { return }
        currentInterval = newInterval
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(newInterval),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.fetch() }
        }
    }

    // MARK: - Fetch

    func fetch() async {
        isFetching = true
        defer { isFetching = false }

        // Read email from auth.json (best-effort, non-blocking)
        let email = readCodexEmail()

        // Query local SQLite for this month's token usage
        let result = await Task.detached(priority: .utility) {
            CodexFetcher.queryMonthlyTokens()
        }.value

        switch result {
        case .failure(let error):
            write(buildCodexErrorService(error: "\(error)"))
        case .success(let tokens):
            write(buildCodexLocalService(tokensUsed: tokens, email: email))
        }
    }

    // MARK: - Local data sources

    /// Read the authenticated user's email from ~/.codex/auth.json (synchronous, tiny file).
    private func readCodexEmail() -> String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard
            let data  = FileManager.default.contents(atPath: path),
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let email = json["email"] as? String
        else { return nil }
        return email
    }

    enum SQLiteError: Error { case dbNotFound, dbOpenFailed, dateError, queryFailed }

    /// Query ~/.codex/state_5.sqlite for this month's total tokens_used.
    /// Runs off the main actor (called via Task.detached).
    nonisolated private static func queryMonthlyTokens() -> Result<Int, SQLiteError> {
        let dbPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".codex/state_5.sqlite")

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return .failure(.dbNotFound)
        }

        var db: OpaquePointer?
        // Open read-only so we don't interfere with Codex's write-ahead log
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return .failure(.dbOpenFailed)
        }
        defer { sqlite3_close(db) }

        // Current month boundary in Unix seconds
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        guard let monthStart = calendar.date(from: comps) else {
            return .failure(.dateError)
        }

        let startTs = Int64(monthStart.timeIntervalSince1970)

        let sql = """
            SELECT COALESCE(SUM(tokens_used), 0)
            FROM threads
            WHERE tokens_used IS NOT NULL
              AND tokens_used > 0
              AND created_at >= ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return .failure(.queryFailed)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, startTs)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return .failure(.queryFailed)
        }

        let total = Int(sqlite3_column_int64(stmt, 0))
        return .success(total)
    }

    // MARK: - Service builders

    /// Build a Service from local SQLite data (token count only, no billing data).
    private func buildCodexLocalService(tokensUsed: Int, email: String?) -> Service {
        let calendar = Calendar.current
        let now = Date()
        let firstOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let startedAt = ISO8601DateFormatter().string(from: firstOfMonth)

        return Service(
            label: "Codex",
            quotas: [
                Quota(
                    type: .tokens,
                    total: nil,          // Codex subscription has no hard token cap
                    used: Double(tokensUsed),
                    unit: "tokens",
                    resetsAt: nil
                )
            ],
            currentSession: SessionSnapshot(
                id: "codex-monthly",
                startedAt: startedAt,
                tokens: Double(tokensUsed),
                time: nil,
                money: nil,
                requests: nil
            ),
            error: nil
        )
    }

    // MARK: - Write helpers

    private func write(_ service: Service) {
        let (path, existing) = readStateFile()
        let updated = mergeCodexService(service, into: existing)
        persist(updated, to: path)
    }

    private func readStateFile() -> (path: String, state: StateFile?) {
        let rawPath = UserDefaults.standard.string(forKey: "stateFilePath")
            ?? "~/.token-hud/state.json"
        let path = (rawPath as NSString).expandingTildeInPath
        let state = (try? Data(contentsOf: URL(fileURLWithPath: path)))
            .flatMap { try? JSONDecoder().decode(StateFile.self, from: $0) }
        return (path, state)
    }

    private func persist(_ state: StateFile, to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
