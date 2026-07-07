// token_hud/State/APIPlatformFetcher.swift
import Foundation
import Observation
import os

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
        initialFetchTask = Task { await fetchAll(allowUserInteraction: false) }
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
            Task { @MainActor [weak self] in await self?.fetchAll(allowUserInteraction: false) }
        }
    }

    // MARK: - Fetch

    enum SingleFetchResult: Equatable {
        case updated
        case noCredential
        case needsAuthorization
        case noData
    }

    func fetchAll(allowUserInteraction: Bool = true) async {
        isFetching = true
        defer { isFetching = false }

        var services: [String: Service] = [:]
        for platform in ["deepseek", "openai", "anthropic", "gemini", "minimax", "mimo", "moonshot", "openrouter", "qwen"] {
            guard hasCredential(for: platform) else { continue }
            if let service = await fetch(platform: platform, allowUserInteraction: allowUserInteraction) {
                services[platform] = service
            }
        }

        // Claude: scan local JSONL files (no credential needed)
        if let claudeService = await fetchClaudeFromJSONL() {
            services["claude"] = claudeService
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

    func fetchSingle(
        platform: String,
        allowUserInteraction: Bool = false
    ) async -> SingleFetchResult {
        isFetching = true
        defer { isFetching = false }
        guard hasCredential(for: platform) else {
            Logger.apiPlatform.debug(" fetchSingle(\(platform)): no credential in Keychain, skipping")
            return .noCredential
        }
        Logger.apiPlatform.debug(" fetchSingle(\(platform)): credential found, fetching...")
        guard let service = await fetch(platform: platform, allowUserInteraction: allowUserInteraction) else {
            Logger.apiPlatform.debug(" fetchSingle(\(platform)): fetch returned nil, skipping")
            return (!allowUserInteraction && platformRequiresSecretRead(platform)) ? .needsAuthorization : .noData
        }
        Logger.apiPlatform.debug(" fetchSingle(\(platform)): got service \(service.label), quotas=\(service.quotas.count), error=\(service.error ?? "nil")")
        let (path, existing) = readStateFile()
        var mergedServices = existing?.services ?? [:]
        mergedServices[platform] = service
        let updated = StateFile(
            version: existing?.version ?? 1,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            services: mergedServices
        )
        persist(updated, to: path)
        Logger.apiPlatform.debug(" fetchSingle(\(platform)): persisted to \(path)")
        return .updated
    }

    private nonisolated func hasCredential(for platform: String) -> Bool {
        // Claude reads local JSONL files, no Keychain credential needed
        if platform == "claude" { return true }
        if KeychainHelper.hasAPIKey(for: platform) { return true }
        if platform == "mimo" {
            if KeychainHelper.hasMiMoConsoleCookie() { return true }
            if KeychainHelper.hasMiMoTokenPlanKey() { return true }
        }
        return false
    }

    private nonisolated func platformRequiresSecretRead(_ platform: String) -> Bool {
        switch platform {
        case "deepseek", "minimax", "mimo":
            return true
        default:
            return false
        }
    }

    nonisolated func fetch(platform: String, allowUserInteraction: Bool = true) async -> Service? {
        switch platform {
        case "claude":     return await fetchClaudeFromJSONL()
        case "deepseek":   return await fetchDeepSeek(allowUserInteraction: allowUserInteraction)
        case "openai":     return await fetchOpenAI()
        case "anthropic":  return await fetchAnthropic()
        case "gemini":     return await fetchGemini()
        case "minimax":    return await fetchMiniMax(allowUserInteraction: allowUserInteraction)
        case "mimo":       return await fetchMiMo(allowUserInteraction: allowUserInteraction)
        case "moonshot":   return await fetchMoonshot(allowUserInteraction: allowUserInteraction)
        case "openrouter": return await fetchOpenRouter(allowUserInteraction: allowUserInteraction)
        case "qwen":       return await fetchQwen(allowUserInteraction: allowUserInteraction)
        default:           return nil
        }
    }

    // MARK: - DeepSeek

    private nonisolated func fetchDeepSeek(allowUserInteraction: Bool) async -> Service? {
        guard let apiKey = KeychainHelper.loadAPIKey(
            for: "deepseek",
            allowUserInteraction: allowUserInteraction
        ) else { return nil }
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
        // Try admin key for usage/costs/credits first
        if let adminKey = KeychainHelper.loadOpenAIAdminKey(allowUserInteraction: false) {
            if let service = await fetchOpenAIWithAdminKey(adminKey) {
                return service
            }
        }
        // Fall back to validation-only with regular API key
        guard KeychainHelper.hasAPIKey(for: "openai") else { return nil }
        return Service(
            label: "OpenAI",
            quotas: [],
            currentSession: nil,
            error: ProviderQueryError.usageUnsupported.rawValue
        )
    }

    private nonisolated func fetchOpenAIWithAdminKey(_ apiKey: String) async -> Service? {
        var quotas: [Quota] = []

        // 1. Credits / balance
        if let creditsQuota = await fetchOpenAICredits(apiKey: apiKey) {
            quotas.append(creditsQuota)
        }

        // 2. Costs (last 30 days)
        if let costQuota = await fetchOpenAICosts(apiKey: apiKey) {
            quotas.append(costQuota)
        }

        guard !quotas.isEmpty else { return nil }

        return Service(
            label: "OpenAI",
            quotas: quotas,
            currentSession: nil,
            error: nil
        )
    }

    private nonisolated func fetchOpenAICredits(apiKey: String) async -> Quota? {
        guard let url = URL(string: "https://api.openai.com/v1/organization/credits") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else { return nil }

            // Response: { "data": { "total_credits": 100.0, "total_used": 60.0, "balance": 40.0 } }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let creditsData = root["data"] as? [String: Any],
                  let total = creditsData["total_credits"] as? Double,
                  let used = creditsData["total_used"] as? Double
            else { return nil }

            return Quota(
                type: .money,
                total: total / 100.0,  // credits are in cents
                used: used / 100.0,
                unit: "USD",
                resetsAt: nil
            )
        } catch {
            Logger.apiPlatform.error("OpenAI credits error: \(error.localizedDescription)")
            return nil
        }
    }

    private nonisolated func fetchOpenAICosts(apiKey: String) async -> Quota? {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let startTime = Int(start.timeIntervalSince1970)

        guard let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startTime)&bucket_width=1d") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else { return nil }

            let totalCost = parseOpenAICostAmount(from: data) ?? 0
            guard totalCost > 0 else { return nil }

            return Quota(
                type: .costSpent,
                total: nil,
                used: totalCost,
                unit: "USD",
                resetsAt: nil
            )
        } catch {
            Logger.apiPlatform.error("OpenAI costs error: \(error.localizedDescription)")
            return nil
        }
    }

    private nonisolated func parseOpenAICostAmount(from data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let amounts = collectAmountValues(in: root)
        guard !amounts.isEmpty else { return nil }
        return amounts.reduce(0, +)
    }

    private nonisolated func collectAmountValues(in value: Any) -> [Double] {
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

    // MARK: - Claude (local JSONL)

    private nonisolated func fetchClaudeFromJSONL() async -> Service? {
        guard let result = ClaudeJSONLScanner.scan(daysBack: 7) else { return nil }

        var quotas: [Quota] = []
        let totalTokens = result.totalInputTokens + result.totalOutputTokens

        // Total token usage
        if totalTokens > 0 {
            quotas.append(Quota(
                type: .tokens,
                total: nil,
                used: totalTokens,
                unit: "tokens",
                resetsAt: nil
            ))
        }

        // Input tokens
        if result.totalInputTokens > 0 {
            quotas.append(Quota(
                type: .inputTokens,
                total: nil,
                used: result.totalInputTokens,
                unit: "tokens",
                resetsAt: nil
            ))
        }

        // Output tokens
        if result.totalOutputTokens > 0 {
            quotas.append(Quota(
                type: .outputTokens,
                total: nil,
                used: result.totalOutputTokens,
                unit: "tokens",
                resetsAt: nil
            ))
        }

        // Cost (only if we have costUSD data)
        if result.totalCostUSD > 0 {
            quotas.append(Quota(
                type: .costSpent,
                total: nil,
                used: result.totalCostUSD,
                unit: "USD",
                resetsAt: nil
            ))
        }

        // Model breakdown
        let modelBreakdown = result.modelBreakdown.prefix(5).map { m in
            ModelUsage(
                model: m.model,
                inputTokens: m.inputTokens,
                outputTokens: m.outputTokens,
                costSpent: nil
            )
        }

        let session = SessionSnapshot(
            id: "claude-local-\(result.sessionCount)-sessions",
            startedAt: result.earliestTimestamp ?? ISO8601DateFormatter().string(from: Date()),
            tokens: totalTokens,
            inputTokens: result.totalInputTokens,
            outputTokens: result.totalOutputTokens,
            costSpent: result.totalCostUSD > 0 ? result.totalCostUSD : nil,
            modelBreakdown: Array(modelBreakdown)
        )

        return Service(
            label: "Claude",
            quotas: quotas,
            currentSession: session,
            error: nil
        )
    }

    // MARK: - Anthropic

    private nonisolated func fetchAnthropic() async -> Service? {
        guard KeychainHelper.hasAPIKey(for: "anthropic") else { return nil }
        return Service(
            label: "Anthropic API",
            quotas: [],
            currentSession: nil,
            error: ProviderQueryError.usageUnsupported.rawValue
        )
    }

    // MARK: - Gemini

    private nonisolated func fetchGemini() async -> Service? {
        guard KeychainHelper.hasAPIKey(for: "gemini") else { return nil }
        return Service(
            label: "Gemini",
            quotas: [],
            currentSession: nil,
            error: ProviderQueryError.usageUnsupported.rawValue
        )
    }

    // MARK: - MiniMax

    /// MiniMax Token Plan usage API.
    /// Official docs expose usage remaining at:
    /// https://www.minimax.io/v1/token_plan/remains
    /// Standard pay-as-you-go Open Platform keys can still validate via /v1/models,
    /// but MiniMax does not document a public balance endpoint for those keys.
    private nonisolated func fetchMiniMax(allowUserInteraction: Bool) async -> Service? {
        guard let apiKey = KeychainHelper.loadAPIKey(
            for: "minimax",
            allowUserInteraction: allowUserInteraction
        ) else {
            Logger.apiPlatform.info("MiniMax: no API key in Keychain")
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
                Logger.apiPlatform.debug("MiniMax: remains response is not HTTPURLResponse")
                return nil
            }

            Logger.apiPlatform.debug("MiniMax: GET /token_plan/remains → status \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                Logger.apiPlatform.error("MiniMax: 401 from remains — invalid API key")
                return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Invalid API key")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                Logger.apiPlatform.error("MiniMax: remains request failed: \(httpResponse.statusCode)")
                // Fall through to /v1/models fallback below
                return await fetchMiniMaxViaModels(apiKey: apiKey)
            }

            // MiniMax wraps business errors inside HTTP 200 with base_resp.
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let baseResp = json["base_resp"] as? [String: Any] {
                let code = baseResp["status_code"] as? Int ?? -1
                let msg = baseResp["status_msg"] as? String ?? "Unknown error"
                Logger.apiPlatform.debug("MiniMax: base_resp: code=\(code) msg=\(msg)")
                if code == 1004 {
                    return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Invalid API key")
                }
                if code == 1013 {
                    // 1013 usually means "not a token plan key" (Open Platform key)
                    return await fetchMiniMaxViaModels(apiKey: apiKey)
                }
                if isMiniMaxNoTokenPlanMessage(msg) {
                    return miniMaxUsageUnsupportedService()
                }
                if code != 0 {
                    return Service(label: "MiniMax", quotas: [], currentSession: nil, error: msg)
                }
                // code == 0: success — continue to parse
            }

            if let service = MiniMaxTokenPlanParser.service(from: data) {
                Logger.apiPlatform.debug("MiniMax: parsed Token Plan usage: quotas=\(service.quotas.count)")
                return service
            }

            Logger.apiPlatform.warning("MiniMax: remains returned 2xx but no quota fields could be parsed")
        } catch {
            Logger.apiPlatform.error("MiniMax: remains network error: \(error.localizedDescription)")
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
                Logger.apiPlatform.debug("MiniMax: response is not HTTPURLResponse")
                return nil
            }

            Logger.apiPlatform.debug("MiniMax: GET /v1/models → status \(httpResponse.statusCode)")
            Logger.apiPlatform.debug("MiniMax: response headers: \(httpResponse.allHeaderFields)")

            if httpResponse.statusCode == 401 {
                Logger.apiPlatform.error("MiniMax: 401 — invalid API key")
                return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Invalid API key")
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let baseResp = json["base_resp"] as? [String: Any] {
                let code = baseResp["status_code"] as? Int ?? -1
                let msg = baseResp["status_msg"] as? String ?? "Unknown error"
                Logger.apiPlatform.debug("MiniMax: base_resp: code=\(code) msg=\(msg)")
                if code == 1004 {
                    return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Invalid API key")
                }
                if isMiniMaxNoTokenPlanMessage(msg) {
                    return miniMaxUsageUnsupportedService()
                }
                if code != 0 {
                    return Service(label: "MiniMax", quotas: [], currentSession: nil, error: msg)
                }
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Request failed (\(httpResponse.statusCode))")
            }

            Logger.apiPlatform.info("MiniMax: key is valid, but no parseable Token Plan usage was returned")
            return miniMaxUsageUnsupportedService()
        } catch {
            Logger.apiPlatform.error("MiniMax: network error: \(error.localizedDescription)")
            return Service(
                label: "MiniMax",
                quotas: [],
                currentSession: nil,
                error: "Network error: \(error.localizedDescription)"
            )
        }
    }

    private nonisolated func isMiniMaxNoTokenPlanMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("token plan subscription") ||
            normalized.contains("no active token plan")
    }

    private nonisolated func miniMaxUsageUnsupportedService() -> Service {
        Service(
            label: "MiniMax",
            quotas: [],
            currentSession: nil,
            error: ProviderQueryError.usageUnsupported.rawValue
        )
    }

    // MARK: - MiMo

    /// Xiaomi MiMo API (api.xiaomimimo.com, OpenAI-compatible).
    /// Calls GET /v1/models to verify the key; no public balance endpoint is known.
    private nonisolated func fetchMiMo(allowUserInteraction: Bool) async -> Service? {
        // 1. Cookie 优先
        if let cookie = KeychainHelper.loadMiMoConsoleCookie(allowUserInteraction: allowUserInteraction) {
            if let service = await fetchMiMoTokenPlan(cookie: cookie) {
                return service
            }
        }

        // 2. Token Plan key
        if let tpKey = KeychainHelper.loadMiMoTokenPlanKey(allowUserInteraction: allowUserInteraction) {
            return await fetchMiMoWithAPIKey(tpKey, keyRole: .tokenPlanKey, allowUserInteraction: allowUserInteraction)
        }

        // 3. 普通 API key（sk- 或 unknown）
        if let apiKey = KeychainHelper.loadAPIKey(
            for: "mimo",
            allowUserInteraction: allowUserInteraction
        ) {
            return await fetchMiMoWithAPIKey(apiKey, keyRole: miMoAPIKeyRole(for: apiKey), allowUserInteraction: allowUserInteraction)
        }

        Logger.apiPlatform.info("MiMo: no API key, Token Plan key, or console cookie in Keychain")
        return nil
    }

    private nonisolated func fetchMiMoWithAPIKey(_ apiKey: String, keyRole: MiMoAPIKeyRole, allowUserInteraction: Bool) async -> Service? {
        var request = URLRequest(url: URL(string: "https://api.xiaomimimo.com/v1/models")!)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 15
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.apiPlatform.debug("MiMo: response is not HTTPURLResponse")
                return nil
            }

            Logger.apiPlatform.debug("MiMo: GET /v1/models → status \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                Logger.apiPlatform.error("MiMo: 401 — invalid API key")
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Invalid API key")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Request failed (\(httpResponse.statusCode))")
            }

            switch keyRole {
            case .payAsYouGoAPIKey:
                Logger.apiPlatform.info("MiMo: pay-as-you-go key is valid, but no usage query API available")
                return Service(
                    label: "MiMo",
                    quotas: [],
                    currentSession: nil,
                    error: ProviderQueryError.usageUnsupported.rawValue
                )
            case .tokenPlanKey:
                Logger.apiPlatform.info("MiMo: Token Plan key is valid, but no public usage endpoint has been verified yet")
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: nil)
            case .unknownAPIKey:
                Logger.apiPlatform.info("MiMo: key is valid, key type is unknown")
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: nil)
            }
        } catch {
            Logger.apiPlatform.error("MiMo: network error: \(error.localizedDescription)")
            return Service(
                label: "MiMo",
                quotas: [],
                currentSession: nil,
                error: "Network error: \(error.localizedDescription)"
            )
        }
    }

    private nonisolated func miMoAPIKeyRole(for key: String) -> MiMoAPIKeyRole {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("tp-") { return .tokenPlanKey }
        if normalized.hasPrefix("sk-") { return .payAsYouGoAPIKey }
        return .unknownAPIKey
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
            Logger.apiPlatform.debug("MiMo: GET /tokenPlan/usage → status \(usageHTTP.statusCode)")

            if usageHTTP.statusCode == 401 {
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Console login expired")
            }
            guard (200..<300).contains(usageHTTP.statusCode) else {
                return Service(label: "MiMo", quotas: [], currentSession: nil, error: "Token Plan usage failed (\(usageHTTP.statusCode))")
            }

            let (detailData, detailResponse) = try await URLSession.shared.data(for: detailRequest)
            let detailHTTP = detailResponse as? HTTPURLResponse
            Logger.apiPlatform.debug("MiMo: GET /tokenPlan/detail → status \(detailHTTP?.statusCode ?? -1)")
            let usableDetailData = (detailHTTP?.statusCode).map { (200..<300).contains($0) } == true ? detailData : nil

            if let service = MiMoTokenPlanParser.service(usageData: usageData, detailData: usableDetailData) {
                return service
            }
            return Service(label: "MiMo", quotas: [], currentSession: nil, error: "No Token Plan usage")
        } catch {
            Logger.apiPlatform.error("MiMo: token plan network error: \(error.localizedDescription)")
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

    // MARK: - Moonshot / Kimi

    private nonisolated func fetchMoonshot(allowUserInteraction: Bool) async -> Service? {
        guard let apiKey = KeychainHelper.loadAPIKey(
            for: "moonshot",
            allowUserInteraction: allowUserInteraction
        ) else { return nil }

        // Try international first, fallback to China mainland
        for host in ["api.moonshot.ai", "api.moonshot.cn"] {
            if let service = await fetchMoonshotBalance(apiKey: apiKey, host: host) {
                return service
            }
        }
        return Service(label: "Moonshot", quotas: [], currentSession: nil, error: ProviderQueryError.networkError.rawValue)
    }

    private nonisolated func fetchMoonshotBalance(apiKey: String, host: String) async -> Service? {
        guard let url = URL(string: "https://\(host)/v1/users/me/balance") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else { return nil }

            // Response: { "available_balance": 100.0, "voucher_balance": 0, "cash_balance": 100.0 }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let available = json["available_balance"] as? Double
            else { return nil }

            let total = available + (json["voucher_balance"] as? Double ?? 0)

            return Service(
                label: "Moonshot",
                quotas: [Quota(type: .money, total: total, used: total - available, unit: "CNY", resetsAt: nil)],
                currentSession: nil,
                error: nil
            )
        } catch {
            return nil
        }
    }

    // MARK: - OpenRouter

    private nonisolated func fetchOpenRouter(allowUserInteraction: Bool) async -> Service? {
        guard let apiKey = KeychainHelper.loadAPIKey(
            for: "openrouter",
            allowUserInteraction: allowUserInteraction
        ) else { return nil }

        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else { return nil }

            // Response: { "data": { "total_credits": 100.0, "total_usage": 60.0 } }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let creditsData = json["data"] as? [String: Any],
                  let totalCredits = creditsData["total_credits"] as? Double,
                  let totalUsage = creditsData["total_usage"] as? Double
            else { return nil }

            return Service(
                label: "OpenRouter",
                quotas: [Quota(type: .money, total: totalCredits, used: totalUsage, unit: "USD", resetsAt: nil)],
                currentSession: nil,
                error: nil
            )
        } catch {
            Logger.apiPlatform.error("OpenRouter credits error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Qwen / DashScope

    private nonisolated func fetchQwen(allowUserInteraction: Bool) async -> Service? {
        guard let apiKey = KeychainHelper.loadAPIKey(
            for: "qwen",
            allowUserInteraction: allowUserInteraction
        ) else { return nil }

        guard let url = URL(string: "https://dashscope.aliyuncs.com/api/v1/user/balance") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else { return nil }

            // Response: { "balance": { "balance": 100.0, "currency": "CNY" } }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let balanceData = json["balance"] as? [String: Any],
                  let balance = balanceData["balance"] as? Double
            else { return nil }

            let currency = balanceData["currency"] as? String ?? "CNY"

            return Service(
                label: "Qwen",
                quotas: [Quota(type: .money, total: nil, used: balance, unit: currency, resetsAt: nil)],
                currentSession: nil,
                error: nil
            )
        } catch {
            Logger.apiPlatform.error("Qwen balance error: \(error.localizedDescription)")
            return nil
        }
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
        // Record daily snapshot for aggregation
        DailySnapshotStore.recordSnapshot(from: state)
    }
}

extension Service {
    func mergingCodexLocalUsage(_ local: Service) -> Service {
        guard error == nil else { return self }
        let localTokenQuotas = local.quotas.filter {
            $0.type == .tokens && $0.unit.lowercased() == "tokens"
        }
        return Service(
            label: label,
            quotas: quotas + localTokenQuotas,
            currentSession: local.currentSession ?? currentSession,
            error: nil
        )
    }

    func appendingCodexCost(_ cost: Double) -> Service {
        var updatedQuotas = quotas
        updatedQuotas.append(Quota(
            type: .costSpent,
            total: nil,
            used: cost,
            unit: "USD",
            resetsAt: nil
        ))
        return Service(
            label: label,
            quotas: updatedQuotas,
            currentSession: currentSession,
            error: nil
        )
    }
}
