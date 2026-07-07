// token_hud/State/CodexFetcher.swift
import Foundation
import Observation
import os

/// Reads Codex usage data from ChatGPT/Codex usage endpoints, then falls back
/// to JSONL session log files at ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl.
/// Results are written into ~/.token-hud/state.json under the "codex" key.
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
        initialFetchTask = Task { await fetch(allowUserInteraction: false) }
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
            Task { @MainActor [weak self] in await self?.fetch(allowUserInteraction: false) }
        }
    }

    // MARK: - Fetch

    func fetch(allowUserInteraction: Bool = true) async {
        isFetching = true
        defer { isFetching = false }

        let identity = readCodexIdentity()
        let whamResult = await fetchCodexWhamUsage(fallbackEmail: identity.email)

        let result = await Task.detached(priority: .utility) {
            CodexFetcher.queryMonthlyUsage()
        }.value

        let localService: Service?
        let localError: ProviderQueryError?
        switch result {
        case .failure(.noSessionsDirectory), .failure(.noSessionFiles):
            localService = nil
            localError = .noLocalSessions
        case .failure(.parseError):
            localService = nil
            localError = .parseError
        case .success(let usage):
            localService = buildCodexLocalService(
                tokensUsed: usage.monthlyTokens,
                primary: usage.primary,
                secondary: usage.secondary,
                email: identity.email,
                plan: identity.plan
            )
            localError = nil
        }

        let baseService: Service
        if let whamResult {
            baseService = localService.map { whamResult.mergingCodexLocalUsage($0) } ?? whamResult
        } else if let localService {
            baseService = localService
        } else {
            baseService = buildCodexErrorService(error: (localError ?? .parseError).rawValue)
        }

        let enriched = await fetchCodexAdminExtras(
            into: baseService,
            allowUserInteraction: allowUserInteraction
        )
        write(enriched)
    }

    // MARK: - Local data sources

    private struct CodexIdentity {
        let email: String?
        let plan: String?
    }

    private struct CodexAuthTokens {
        let accessToken: String
        let accountID: String?
    }

    /// Read the authenticated user's identity from ~/.codex/auth.json (synchronous, tiny file).
    private func readCodexIdentity() -> CodexIdentity {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard
            let data   = FileManager.default.contents(atPath: path),
            let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let idTok  = tokens["id_token"] as? String,
            let parts  = Optional(idTok.components(separatedBy: ".")),
            parts.count == 3
        else { return CodexIdentity(email: nil, plan: nil) }
        var b64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard
            let data2   = Data(base64Encoded: b64),
            let payload = try? JSONSerialization.jsonObject(with: data2) as? [String: Any]
        else { return CodexIdentity(email: nil, plan: nil) }
        let claim = codexAuthClaim(from: payload)
        return CodexIdentity(
            email: claim.email,
            plan: claim.plan
        )
    }

    private func readCodexAuthTokens() -> CodexAuthTokens? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard
            let data = FileManager.default.contents(atPath: path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            !accessToken.isEmpty
        else { return nil }
        return CodexAuthTokens(
            accessToken: accessToken,
            accountID: tokens["account_id"] as? String
        )
    }

    private func fetchCodexWhamUsage(fallbackEmail: String?) async -> Service? {
        guard let tokens = readCodexAuthTokens(),
              let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let accountID = tokens.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 401 {
                return buildCodexErrorService(error: ProviderQueryError.tokenExpired.rawValue)
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                Logger.codex.error("wham usage request failed (\(httpResponse.statusCode)); falling back to local sessions")
                return nil
            }
            guard let service = CodexWhamUsageParser.service(from: data, fallbackEmail: fallbackEmail) else {
                Logger.codex.error("wham usage response could not be parsed; falling back to local sessions")
                return nil
            }
            return service
        } catch {
            Logger.codex.error("wham usage network error: \(error.localizedDescription); falling back to local sessions")
            return nil
        }
    }

    // MARK: - JSONL types

    private enum CodexReadError: Error {
        case noSessionsDirectory
        case noSessionFiles
        case parseError
    }

    private struct RateLimitInfo {
        let usedPercent: Double
        let windowSeconds: Double
        let resetsAt: Date
    }

    private struct CodexUsageResult {
        let monthlyTokens: Int
        let primary: RateLimitInfo?
        let secondary: RateLimitInfo?
    }

    private struct ParsedSession {
        let totalTokens: Int
        let primary: RateLimitInfo?
        let secondary: RateLimitInfo?
    }

    // MARK: - JSONL query

    /// Scan ~/.codex/sessions/YYYY/MM/**/*.jsonl for this month's usage.
    /// Runs off the main actor (called via Task.detached).
    nonisolated private static func queryMonthlyUsage() -> Result<CodexUsageResult, CodexReadError> {
        let sessionsBase = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".codex/sessions")

        guard FileManager.default.fileExists(atPath: sessionsBase) else {
            return .failure(.noSessionsDirectory)
        }

        let calendar = Calendar.current
        let now      = Date()
        let year     = calendar.component(.year,  from: now)
        let month    = calendar.component(.month, from: now)
        let monthDir = (sessionsBase as NSString)
            .appendingPathComponent(String(format: "%04d/%02d", year, month))

        guard FileManager.default.fileExists(atPath: monthDir) else {
            return .failure(.noSessionFiles)
        }

        // Collect all rollout-*.jsonl paths under YYYY/MM/DD/
        var jsonlPaths: [String] = []
        let fm = FileManager.default
        if let dayDirs = try? fm.contentsOfDirectory(atPath: monthDir) {
            for day in dayDirs.sorted() {
                let dayPath = (monthDir as NSString).appendingPathComponent(day)
                if let files = try? fm.contentsOfDirectory(atPath: dayPath) {
                    for filename in files.sorted() where filename.hasSuffix(".jsonl") {
                        jsonlPaths.append((dayPath as NSString).appendingPathComponent(filename))
                    }
                }
            }
        }

        guard !jsonlPaths.isEmpty else {
            return .failure(.noSessionFiles)
        }

        // Parse each file; track the most recently modified for rate limits
        var monthlyTokens = 0
        var latestModDate = Date.distantPast
        var latestSession: ParsedSession?

        for path in jsonlPaths {
            guard let parsed = parseSession(at: path) else { continue }
            monthlyTokens += parsed.totalTokens

            let modDate = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
                ?? Date.distantPast
            if modDate > latestModDate {
                latestModDate  = modDate
                latestSession  = parsed
            }
        }

        if monthlyTokens == 0 && latestSession == nil {
            return .failure(.parseError)
        }

        return .success(CodexUsageResult(
            monthlyTokens: monthlyTokens,
            primary:       latestSession?.primary,
            secondary:     latestSession?.secondary
        ))
    }

    /// Parse a single rollout-*.jsonl file. Scans in reverse to find the last
    /// token_count event with non-null info, which holds the session's cumulative total.
    nonisolated private static func parseSession(at path: String) -> ParsedSession? {
        guard
            let raw   = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }

        let lines = raw.components(separatedBy: "\n")

        for line in lines.reversed() {
            guard
                !line.isEmpty,
                let data    = line.data(using: .utf8),
                let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["type"] as? String == "event_msg",
                let payload = json["payload"] as? [String: Any],
                payload["type"] as? String == "token_count",
                let info    = payload["info"] as? [String: Any],   // null info → skip
                let totUsage = info["total_token_usage"] as? [String: Any],
                let total   = totUsage["total_tokens"] as? Int
            else { continue }

            // Found the last qualifying event; extract rate limits (best-effort)
            var primary:   RateLimitInfo?
            var secondary: RateLimitInfo?
            if let rl = payload["rate_limits"] as? [String: Any] {
                primary   = parseRateLimit(rl["primary"])
                secondary = parseRateLimit(rl["secondary"])
            }

            return ParsedSession(
                totalTokens: total,
                primary:     primary,
                secondary:   secondary
            )
        }
        return nil
    }

    nonisolated private static func parseRateLimit(_ raw: Any?) -> RateLimitInfo? {
        guard
            let d           = raw as? [String: Any],
            let usedPct     = d["used_percent"] as? Double,
            let winMinutes  = d["window_minutes"] as? Int,
            let resetsAtTs  = d["resets_at"] as? Int
        else { return nil }
        return RateLimitInfo(
            usedPercent:   usedPct,
            windowSeconds: Double(winMinutes) * 60,
            resetsAt:      Date(timeIntervalSince1970: Double(resetsAtTs))
        )
    }

    // MARK: - Service builders

    private func buildCodexLocalService(
        tokensUsed: Int,
        primary:    RateLimitInfo?,
        secondary:  RateLimitInfo?,
        email:      String?,
        plan:       String?
    ) -> Service {
        let calendar     = Calendar.current
        let now          = Date()
        let firstOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let fmt       = ISO8601DateFormatter()
        let startedAt = fmt.string(from: firstOfMonth)

        var quotas: [Quota] = [
            Quota(type: .tokens, total: nil, used: Double(tokensUsed), unit: "tokens", resetsAt: nil)
        ]

        // 5h rate-limit window (window_minutes == 300 → 18000s → "5h window" label)
        if let p = primary {
            quotas.append(Quota(
                type:     .time,
                total:    p.windowSeconds,
                used:     p.windowSeconds * (p.usedPercent / 100),
                unit:     "seconds",
                resetsAt: fmt.string(from: p.resetsAt)
            ))
        }

        // 7d rate-limit window (window_minutes == 10080 → 604800s → "7d window" label)
        if let s = secondary {
            quotas.append(Quota(
                type:     .time,
                total:    s.windowSeconds,
                used:     s.windowSeconds * (s.usedPercent / 100),
                unit:     "seconds",
                resetsAt: fmt.string(from: s.resetsAt)
            ))
        }

        return Service(
            label: WidgetValueComputer.codexServiceLabel(plan: plan),
            quotas: quotas,
            currentSession: SessionSnapshot(
                id:        "codex-monthly",
                startedAt: startedAt,
                tokens:    Double(tokensUsed),
                time:      nil,
                money:     nil,
                requests:  nil
            ),
            error: nil
        )
    }

    // MARK: - OpenAI Admin extras

    nonisolated private func fetchCodexAdminExtras(
        into service: Service,
        allowUserInteraction: Bool
    ) async -> Service {
        guard allowUserInteraction,
              KeychainHelper.hasCodexAdminKey(),
              let apiKey = KeychainHelper.loadCodexAdminKey(allowUserInteraction: allowUserInteraction)
        else { return service }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let startTime = Int(start.timeIntervalSince1970)

        guard let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startTime)&bucket_width=1d") else {
            return service
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return service }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                Logger.codex.error("Usage/Costs permission denied (\(httpResponse.statusCode))")
                return service
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                Logger.codex.error("Costs request failed (\(httpResponse.statusCode))")
                return service
            }

            guard let cost = Self.parseOpenAICostAmount(from: data), cost > 0 else {
                Logger.codex.info("Costs response contained no positive amount")
                return service
            }
            return service.appendingCodexCost(cost)
        } catch {
            Logger.codex.error("Network error: \(error.localizedDescription)")
            return service
        }
    }

    nonisolated private static func parseOpenAICostAmount(from data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let amounts = collectAmountValues(in: root)
        guard !amounts.isEmpty else { return nil }
        return amounts.reduce(0, +)
    }

    nonisolated private static func collectAmountValues(in value: Any) -> [Double] {
        if let dict = value as? [String: Any] {
            var values: [Double] = []
            if let amount = dict["amount"] as? [String: Any] {
                if let numeric = amount["value"] as? Double {
                    values.append(numeric)
                } else if let intValue = amount["value"] as? Int {
                    values.append(Double(intValue))
                } else if let stringValue = amount["value"] as? String,
                          let numeric = Double(stringValue) {
                    values.append(numeric)
                }
            }
            for child in dict.values {
                values.append(contentsOf: collectAmountValues(in: child))
            }
            return values
        }
        if let array = value as? [Any] {
            return array.flatMap { collectAmountValues(in: $0) }
        }
        return []
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
