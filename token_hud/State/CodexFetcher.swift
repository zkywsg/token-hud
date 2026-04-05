// token_hud/State/CodexFetcher.swift
import Foundation
import Observation

/// Fetches Codex billing/usage data on a configurable timer and writes it
/// into ~/.token-hud/state.json under the "codex" key.
///
/// Lifecycle: init → starts timer + fires immediately.
/// Call stop() before the object is discarded.
@Observable
@MainActor
final class CodexFetcher {

    private(set) var isFetching = false

    private var timer: Timer?
    private var currentInterval: Int = 0
    private var defaultsObserver: NSObjectProtocol?
    private var initialFetchTask: Task<Void, Never>?

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

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
        let authPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".codex/auth.json")

        guard
            let data   = FileManager.default.contents(atPath: authPath),
            let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let access = tokens["access_token"] as? String
        else {
            await write(buildCodexErrorService(error: "notConfigured"))
            return
        }

        guard !isCodexTokenExpired(token: access) else {
            await write(buildCodexErrorService(error: "tokenExpired"))
            return
        }

        async let usageResult  = fetchBillingUsage(token: access)
        async let subResult    = fetchSubscription(token: access)
        async let tokResult    = fetchTokenUsage(token: access)

        let (usage, sub, toks) = await (usageResult, subResult, tokResult)

        // Network errors preserve existing quota data (stale data > no data)
        if case .failure(.networkError) = usage {
            await writeError("networkError", preserveExisting: true); return
        }
        if case .failure(.networkError) = sub {
            await writeError("networkError", preserveExisting: true); return
        }
        // Auth/HTTP errors clear quota data (something is wrong that needs fixing)
        if case .failure(let e) = usage {
            await writeError(e.label, preserveExisting: false); return
        }
        if case .failure(let e) = sub {
            await writeError(e.label, preserveExisting: false); return
        }

        let costUsd    = (try? usage.get()) ?? 0
        let limitUsd   = (try? sub.get()) ?? 0
        // fetchTokenUsage is optional — if it fails, token count defaults to 0 (quota/cost data still shows)
        let tokensUsed = (try? toks.get()) ?? 0

        await write(buildCodexService(
            costUsd: costUsd,
            costLimitUsd: limitUsd,
            tokensUsed: tokensUsed
        ))
    }

    // MARK: - API calls

    private enum FetchError: Error {
        case networkError, forbidden, httpError(Int)

        var label: String {
            switch self {
            case .networkError:      return "networkError"
            case .forbidden:         return "apiForbidden"
            case .httpError(let c):  return "apiError(\(c))"
            }
        }
    }

    private func fetchBillingUsage(token: String) async -> Result<Double, FetchError> {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let startDate = String(format: "%04d-%02d-01", comps.year ?? 2000, comps.month ?? 1)
        let endDate = monthFormatter.string(from: now)

        var urlComps = URLComponents(string: "https://api.openai.com/dashboard/billing/usage")!
        urlComps.queryItems = [
            URLQueryItem(name: "start_date", value: startDate),
            URLQueryItem(name: "end_date",   value: endDate),
        ]
        var req = URLRequest(url: urlComps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failure(.httpError(0)) }
            if http.statusCode == 403 { return .failure(.forbidden) }
            guard http.statusCode == 200 else { return .failure(.httpError(http.statusCode)) }
            struct R: Decodable {
                let totalUsage: Double
                enum CodingKeys: String, CodingKey { case totalUsage = "total_usage" }
            }
            return .success((try JSONDecoder().decode(R.self, from: data)).totalUsage / 100.0)
        } catch { return .failure(.networkError) }
    }

    private func fetchSubscription(token: String) async -> Result<Double, FetchError> {
        var req = URLRequest(url: URL(string: "https://api.openai.com/dashboard/billing/subscription")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failure(.httpError(0)) }
            if http.statusCode == 403 { return .failure(.forbidden) }
            guard http.statusCode == 200 else { return .failure(.httpError(http.statusCode)) }
            struct R: Decodable {
                let hardLimitUsd: Double
                enum CodingKeys: String, CodingKey { case hardLimitUsd = "hard_limit_usd" }
            }
            let decoded = try JSONDecoder().decode(R.self, from: data)
            return .success(decoded.hardLimitUsd)
        } catch { return .failure(.networkError) }
    }

    private func fetchTokenUsage(token: String) async -> Result<Int, FetchError> {
        var comps = URLComponents(string: "https://api.openai.com/v1/usage")!
        comps.queryItems = [URLQueryItem(name: "date", value: monthFormatter.string(from: Date()))]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failure(.httpError(0)) }
            if http.statusCode == 403 { return .failure(.forbidden) }
            guard http.statusCode == 200 else { return .failure(.httpError(http.statusCode)) }
            struct Entry: Decodable {
                let nContextTokensTotal: Int
                let nGeneratedTokensTotal: Int
                enum CodingKeys: String, CodingKey {
                    case nContextTokensTotal   = "n_context_tokens_total"
                    case nGeneratedTokensTotal = "n_generated_tokens_total"
                }
            }
            struct R: Decodable { let data: [Entry] }
            let decoded = try JSONDecoder().decode(R.self, from: data)
            let total = decoded.data.reduce(0) { $0 + $1.nContextTokensTotal + $1.nGeneratedTokensTotal }
            return .success(total)
        } catch { return .failure(.networkError) }
    }

    // MARK: - Write

    // Write a fully-built service (success path).
    private func write(_ service: Service) async {
        let (path, existing) = readStateFile()
        let updated = mergeCodexService(service, into: existing)
        persist(updated, to: path)
    }

    // Write only an error flag.
    // When preserveExisting is true and the current state.json already has
    // Codex quota data, the quotas are kept so the overlay stays populated.
    private func writeError(_ error: String, preserveExisting: Bool) async {
        let (path, existing) = readStateFile()
        let currentCodex = existing?.services["codex"]
        let service: Service
        if preserveExisting, let prev = currentCodex, !prev.quotas.isEmpty {
            service = Service(
                label: prev.label,
                quotas: prev.quotas,
                currentSession: prev.currentSession,
                error: error
            )
        } else {
            service = buildCodexErrorService(error: error)
        }
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
