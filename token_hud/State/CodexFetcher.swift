// token_hud/State/CodexFetcher.swift
import Foundation
import Observation

/// Reads Codex usage data from JSONL session log files at
/// ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl and writes it into
/// ~/.token-hud/state.json under the "codex" key.
///
/// No network requests are made — all data comes from Codex's own session logs.
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

        let email = readCodexEmail()

        let result = await Task.detached(priority: .utility) {
            CodexFetcher.queryMonthlyUsage()
        }.value

        switch result {
        case .failure(.noSessionsDirectory), .failure(.noSessionFiles):
            write(buildCodexErrorService(error: "No sessions yet"))
        case .failure(.parseError):
            write(buildCodexErrorService(error: "parseError"))
        case .success(let usage):
            write(buildCodexLocalService(
                tokensUsed: usage.monthlyTokens,
                primary: usage.primary,
                secondary: usage.secondary,
                email: email
            ))
        }
    }

    // MARK: - Local data sources

    /// Read the authenticated user's email from ~/.codex/auth.json (synchronous, tiny file).
    private func readCodexEmail() -> String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard
            let data   = FileManager.default.contents(atPath: path),
            let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let idTok  = tokens["id_token"] as? String,
            let parts  = Optional(idTok.components(separatedBy: ".")),
            parts.count == 3
        else { return nil }
        var b64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard
            let data2   = Data(base64Encoded: b64),
            let payload = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
            let email   = payload["email"] as? String
        else { return nil }
        return email
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
        email:      String?
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
            label: "Codex",
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

// MARK: - APIPlatformFetcher

@Observable
@MainActor
final class APIPlatformFetcher {
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
        initialFetchTask = Task { await fetchAll() }
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
            Task { @MainActor [weak self] in await self?.fetchAll() }
        }
    }

    // MARK: - Fetch

    func fetchAll() async {
        isFetching = true
        defer { isFetching = false }

        var services: [String: Service] = [:]
        for platform in ["deepseek", "openai", "anthropic", "gemini", "minimax", "mimo"] {
            guard hasCredential(for: platform) else { continue }
            if let service = await fetch(platform: platform) {
                services[platform] = service
            }
        }

        guard !services.isEmpty else { return }

        let (path, existing) = readStateFile()
        var mergedServices = existing?.services ?? [:]
        for (key, service) in services {
            mergedServices[key] = service
        }
        let updated = StateFile(
            version: existing?.version ?? 1,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            services: mergedServices
        )
        persist(updated, to: path)
    }

    func fetchSingle(platform: String) async {
        isFetching = true
        defer { isFetching = false }
        guard hasCredential(for: platform) else {
            print("[APIPlatformFetcher] fetchSingle(\(platform)): no credential in Keychain, skipping")
            return
        }
        print("[APIPlatformFetcher] fetchSingle(\(platform)): credential found, fetching...")
        guard let service = await fetch(platform: platform) else {
            print("[APIPlatformFetcher] fetchSingle(\(platform)): fetch returned nil, skipping")
            return
        }
        print("[APIPlatformFetcher] fetchSingle(\(platform)): got service \(service.label), quotas=\(service.quotas.count), error=\(service.error ?? "nil")")
        let (path, existing) = readStateFile()
        var mergedServices = existing?.services ?? [:]
        mergedServices[platform] = service
        let updated = StateFile(
            version: existing?.version ?? 1,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            services: mergedServices
        )
        persist(updated, to: path)
        print("[APIPlatformFetcher] fetchSingle(\(platform)): persisted to \(path)")
    }

    private nonisolated func hasCredential(for platform: String) -> Bool {
        if KeychainHelper.loadAPIKey(for: platform) != nil { return true }
        if platform == "mimo", KeychainHelper.loadMiMoConsoleCookie() != nil { return true }
        return false
    }

    nonisolated func fetch(platform: String) async -> Service? {
        switch platform {
        case "deepseek": return await fetchDeepSeek()
        case "openai":   return await fetchOpenAI()
        case "anthropic":return await fetchAnthropic()
        case "gemini":   return await fetchGemini()
        case "minimax":  return await fetchMiniMax()
        case "mimo":     return await fetchMiMo()
        default:         return nil
        }
    }

    // MARK: - DeepSeek

    private nonisolated func fetchDeepSeek() async -> Service? {
        guard let apiKey = KeychainHelper.loadAPIKey(for: "deepseek") else { return nil }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 401 {
                return Service(
                    label: "DeepSeek",
                    quotas: [],
                    currentSession: nil,
                    error: "Invalid API key"
                )
            }
            guard (200..<300).contains(httpResponse.statusCode) else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let isAvailable = json["is_available"] as? Bool ?? false
            guard isAvailable,
                  let balanceInfos = json["balance_infos"] as? [[String: Any]],
                  let first = balanceInfos.first,
                  let totalBalanceStr = first["total_balance"] as? String,
                  let totalBalance = Double(totalBalanceStr)
            else {
                return Service(
                    label: "DeepSeek",
                    quotas: [],
                    currentSession: nil,
                    error: "No balance info"
                )
            }

            let currency = first["currency"] as? String ?? "CNY"

            return Service(
                label: "DeepSeek",
                quotas: [
                    Quota(type: .money, total: nil, used: totalBalance, unit: currency, resetsAt: nil)
                ],
                currentSession: nil,
                error: nil
            )
        } catch {
            return Service(
                label: "DeepSeek",
                quotas: [],
                currentSession: nil,
                error: "Network error"
            )
        }
    }

    // MARK: - OpenAI

    private nonisolated func fetchOpenAI() async -> Service? {
        guard KeychainHelper.loadAPIKey(for: "openai") != nil else { return nil }
        // OpenAI does not expose a public balance endpoint that works
        // consistently with standard API keys. Skip for now.
        return nil
    }

    // MARK: - Anthropic

    private nonisolated func fetchAnthropic() async -> Service? {
        guard KeychainHelper.loadAPIKey(for: "anthropic") != nil else { return nil }
        // Anthropic does not expose a public balance API.
        return nil
    }

    // MARK: - Gemini

    private nonisolated func fetchGemini() async -> Service? {
        guard KeychainHelper.loadAPIKey(for: "gemini") != nil else { return nil }
        // Gemini billing is managed through Google Cloud; no simple balance endpoint.
        return nil
    }

    // MARK: - MiniMax

    /// MiniMax Token Plan usage API.
    /// Official docs expose usage remaining at:
    /// https://www.minimax.io/v1/token_plan/remains
    /// Standard pay-as-you-go Open Platform keys can still validate via /v1/models,
    /// but MiniMax does not document a public balance endpoint for those keys.
    private nonisolated func fetchMiniMax() async -> Service? {
        guard let apiKey = KeychainHelper.loadAPIKey(for: "minimax") else {
            print("[MiniMax] no API key in Keychain")
            return nil
        }

        var usageRequest = URLRequest(url: URL(string: "https://www.minimax.io/v1/token_plan/remains")!)
        usageRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        usageRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        usageRequest.timeoutInterval = 15
        usageRequest.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: usageRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[MiniMax] remains response is not HTTPURLResponse")
                return nil
            }

            print("[MiniMax] GET /token_plan/remains → status \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                print("[MiniMax] 401 from remains — invalid API key")
                return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Invalid API key")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                print("[MiniMax] remains request failed: \(httpResponse.statusCode)")
                // Fall through to /v1/models fallback below
                return await fetchMiniMaxViaModels(apiKey: apiKey)
            }

            // MiniMax wraps business errors inside HTTP 200 with base_resp.
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let baseResp = json["base_resp"] as? [String: Any] {
                let code = baseResp["status_code"] as? Int ?? -1
                let msg = baseResp["status_msg"] as? String ?? "Unknown error"
                print("[MiniMax] base_resp: code=\(code) msg=\(msg)")
                if code == 1004 {
                    return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Invalid API key")
                }
                if code == 1013 {
                    // 1013 usually means "not a token plan key" (Open Platform key)
                    return await fetchMiniMaxViaModels(apiKey: apiKey)
                }
                if code != 0 {
                    return Service(label: "MiniMax", quotas: [], currentSession: nil, error: msg)
                }
                // code == 0: success — continue to parse
            }

            if let service = MiniMaxTokenPlanParser.service(from: data) {
                print("[MiniMax] parsed Token Plan usage: quotas=\(service.quotas.count)")
                return service
            }

            print("[MiniMax] remains returned 2xx but no quota fields could be parsed")
        } catch {
            print("[MiniMax] remains network error: \(error.localizedDescription)")
        }

        return await fetchMiniMaxViaModels(apiKey: apiKey)
    }

    /// Fallback for Open Platform (pay-as-you-go) keys: validate via /v1/models.
    private nonisolated func fetchMiniMaxViaModels(apiKey: String) async -> Service? {
        var request = URLRequest(url: URL(string: "https://api.minimax.io/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[MiniMax] response is not HTTPURLResponse")
                return nil
            }

            print("[MiniMax] GET /v1/models → status \(httpResponse.statusCode)")
            print("[MiniMax] response headers: \(httpResponse.allHeaderFields)")

            if httpResponse.statusCode == 401 {
                print("[MiniMax] 401 — invalid API key")
                return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Invalid API key")
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let baseResp = json["base_resp"] as? [String: Any] {
                let code = baseResp["status_code"] as? Int ?? -1
                let msg = baseResp["status_msg"] as? String ?? "Unknown error"
                print("[MiniMax] base_resp: code=\(code) msg=\(msg)")
                if code == 1004 {
                    return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Invalid API key")
                }
                if code != 0 {
                    return Service(label: "MiniMax", quotas: [], currentSession: nil, error: msg)
                }
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Request failed (\(httpResponse.statusCode))")
            }

            print("[MiniMax] key is valid, but no parseable Token Plan usage was returned")
            return Service(label: "MiniMax", quotas: [], currentSession: nil, error: nil)
        } catch {
            print("[MiniMax] network error: \(error.localizedDescription)")
            return Service(
                label: "MiniMax",
                quotas: [],
                currentSession: nil,
                error: "Network error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - MiMo

    /// Xiaomi MiMo API (api.xiaomimimo.com, OpenAI-compatible).
    /// Calls GET /v1/models to verify the key; no public balance endpoint is known.
    private nonisolated func fetchMiMo() async -> Service? {
        if let cookie = KeychainHelper.loadMiMoConsoleCookie() {
            if let service = await fetchMiMoTokenPlan(cookie: cookie) {
                return service
            }
        }

        guard let apiKey = KeychainHelper.loadAPIKey(for: "mimo") else {
            print("[MiMo] no API key or console cookie in Keychain")
            return nil
        }
        var request = URLRequest(url: URL(string: "https://api.xiaomimimo.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[MiMo] response is not HTTPURLResponse")
                return nil
            }

            print("[MiMo] GET /v1/models → status \(httpResponse.statusCode)")
            print("[MiMo] response headers: \(httpResponse.allHeaderFields)")

            if httpResponse.statusCode == 401 {
                print("[MiMo] 401 — invalid API key")
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Invalid API key")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Request failed (\(httpResponse.statusCode))")
            }

            print("[MiMo] key is valid, no balance endpoint available")
            return Service(label: "MiMo", quotas: [], currentSession: nil, error: nil)
        } catch {
            print("[MiMo] network error: \(error.localizedDescription)")
            return Service(
                label: "MiMo",
                quotas: [],
                currentSession: nil,
                error: "Network error: \(error.localizedDescription)"
            )
        }
    }

    private nonisolated func fetchMiMoTokenPlan(cookie: String) async -> Service? {
        let normalizedCookie = normalizedCookieHeader(cookie)
        var usageRequest = URLRequest(url: URL(string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage")!)
        usageRequest.setValue(normalizedCookie, forHTTPHeaderField: "Cookie")
        usageRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        usageRequest.timeoutInterval = 15
        usageRequest.httpMethod = "GET"

        var detailRequest = URLRequest(url: URL(string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/detail")!)
        detailRequest.setValue(normalizedCookie, forHTTPHeaderField: "Cookie")
        detailRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        detailRequest.timeoutInterval = 15
        detailRequest.httpMethod = "GET"

        do {
            let (usageData, usageResponse) = try await URLSession.shared.data(for: usageRequest)
            guard let usageHTTP = usageResponse as? HTTPURLResponse else { return nil }
            print("[MiMo] GET /tokenPlan/usage → status \(usageHTTP.statusCode)")

            if usageHTTP.statusCode == 401 {
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Console login expired")
            }
            guard (200..<300).contains(usageHTTP.statusCode) else {
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Token Plan usage failed (\(usageHTTP.statusCode))")
            }

            let (detailData, detailResponse) = try await URLSession.shared.data(for: detailRequest)
            let detailHTTP = detailResponse as? HTTPURLResponse
            print("[MiMo] GET /tokenPlan/detail → status \(detailHTTP?.statusCode ?? -1)")
            let usableDetailData = (detailHTTP?.statusCode).map { (200..<300).contains($0) } == true ? detailData : nil

            if let service = MiMoTokenPlanParser.service(usageData: usageData, detailData: usableDetailData) {
                return service
            }
            return Service(label: "MiMo", quotas: [], currentSession: nil, error: "No Token Plan usage")
        } catch {
            print("[MiMo] token plan network error: \(error.localizedDescription)")
            return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Network error: \(error.localizedDescription)")
        }
    }

    private nonisolated func normalizedCookieHeader(_ cookie: String) -> String {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("cookie:") {
            return String(trimmed.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    // MARK: - State helpers

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
