// Sources/token_hudCore/StateModel.swift
import Foundation

public enum QuotaType: String, Codable, Sendable {
    case time, tokens, money, requests
    case inputTokens     = "input_tokens"
    case outputTokens    = "output_tokens"
    case dailyTokens     = "daily_tokens"
    case monthlyTokens   = "monthly_tokens"
    case dailyRequests   = "daily_requests"
    case monthlyRequests = "monthly_requests"
    case costSpent       = "cost_spent"
}

public struct Quota: Codable, Sendable {
    public let type: QuotaType
    public let total: Double?        // nil = no hard cap (e.g. Codex subscription)
    public let used: Double
    public let unit: String
    public let resetsAt: String?   // ISO 8601

    public var remaining: Double { (total ?? 0) - used }
    public var usedFraction: Double {
        guard let t = total, t > 0 else { return 0 }
        return used / t
    }
}

public struct ModelUsage: Codable, Sendable, Equatable {
    public let model: String
    public let inputTokens: Double?
    public let outputTokens: Double?
    public let costSpent: Double?
    public let requests: Double?

    public init(model: String, inputTokens: Double? = nil, outputTokens: Double? = nil,
                costSpent: Double? = nil, requests: Double? = nil) {
        self.model = model; self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.costSpent = costSpent; self.requests = requests
    }
}

public struct SessionSnapshot: Codable, Sendable {
    public let id: String
    public let startedAt: String   // ISO 8601
    public let tokens: Double?
    public let time: Double?
    public let money: Double?
    public let requests: Double?
    public let inputTokens: Double?
    public let outputTokens: Double?
    public let costSpent: Double?
    public let modelBreakdown: [ModelUsage]?

    public init(id: String, startedAt: String, tokens: Double? = nil, time: Double? = nil,
                money: Double? = nil, requests: Double? = nil,
                inputTokens: Double? = nil, outputTokens: Double? = nil, costSpent: Double? = nil,
                modelBreakdown: [ModelUsage]? = nil) {
        self.id = id; self.startedAt = startedAt
        self.tokens = tokens; self.time = time; self.money = money; self.requests = requests
        self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.costSpent = costSpent
        self.modelBreakdown = modelBreakdown
    }
}

public struct Service: Codable, Sendable {
    public let label: String
    public let quotas: [Quota]
    public let currentSession: SessionSnapshot?
    public let error: String?

    public init(label: String, quotas: [Quota], currentSession: SessionSnapshot?, error: String? = nil) {
        self.label = label
        self.quotas = quotas
        self.currentSession = currentSession
        self.error = error
    }
}

public struct StateFile: Codable, Sendable {
    public let version: Int
    public let updatedAt: String
    public let services: [String: Service]

    public static let preview = StateFile(
        version: 1,
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        services: [
            "claude": Service(
                label: "Claude",
                quotas: [
                    Quota(type: .time,   total: 28800, used: 10800, unit: "seconds",
                          resetsAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 6300))),
                    Quota(type: .tokens, total: 200_000, used: 80_000, unit: "tokens", resetsAt: nil)
                ],
                currentSession: SessionSnapshot(
                    id: "preview-session",
                    startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -3600)),
                    tokens: 45_000, time: 3600, money: 0.54, requests: 12,
                    modelBreakdown: [
                        ModelUsage(model: "claude-sonnet-4-20250514", inputTokens: 30_000, outputTokens: 12_000, costSpent: 0.38, requests: 8),
                        ModelUsage(model: "claude-haiku-4-20250414", inputTokens: 18_000, outputTokens: 8_000, costSpent: 0.16, requests: 4)
                    ]
                )
            ),
            "openai": Service(
                label: "OpenAI",
                quotas: [
                    Quota(type: .money, total: 5.0, used: 1.5, unit: "USD", resetsAt: nil)
                ],
                currentSession: nil
            ),
            "codex": Service(
                label: "Codex",
                quotas: [
                    Quota(type: .tokens, total: nil, used: 31_592_669, unit: "tokens", resetsAt: nil),
                    // Primary 5h rate-limit window (~70% used, ~1h 30m remaining)
                    Quota(type: .time, total: 18_000, used: 12_600, unit: "seconds",
                          resetsAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 5_400))),
                    // Secondary 7d rate-limit window (~50% used, ~3.5d remaining)
                    Quota(type: .time, total: 604_800, used: 302_400, unit: "seconds",
                          resetsAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 302_400)))
                ],
                currentSession: SessionSnapshot(
                    id: "codex-preview",
                    startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -86400)),
                    tokens: 31_592_669, time: nil, money: nil, requests: nil
                )
            ),
            "gemini": Service(
                label: "Gemini",
                quotas: [
                    Quota(type: .dailyRequests, total: 1500, used: 420, unit: "requests",
                          resetsAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 43200))),
                    Quota(type: .dailyTokens, total: 1_000_000, used: 350_000, unit: "tokens",
                          resetsAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 43200)))
                ],
                currentSession: SessionSnapshot(
                    id: "gemini-preview",
                    startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -1800)),
                    tokens: 12_500, requests: 8,
                    inputTokens: 8_200, outputTokens: 4_300, costSpent: 0.035
                )
            ),
            "deepseek": Service(
                label: "DeepSeek",
                quotas: [
                    Quota(type: .money, total: 10.0, used: 3.75, unit: "USD", resetsAt: nil),
                    Quota(type: .monthlyTokens, total: 5_000_000, used: 2_100_000, unit: "tokens", resetsAt: nil)
                ],
                currentSession: SessionSnapshot(
                    id: "deepseek-preview",
                    startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -900)),
                    tokens: 28_000, requests: 5,
                    inputTokens: 18_000, outputTokens: 10_000, costSpent: 0.12
                )
            ),
            "anthropic": Service(
                label: "Anthropic API",
                quotas: [
                    Quota(type: .money, total: 25.0, used: 8.40, unit: "USD", resetsAt: nil),
                    Quota(type: .monthlyRequests, total: 5000, used: 1250, unit: "requests", resetsAt: nil)
                ],
                currentSession: SessionSnapshot(
                    id: "anthropic-preview",
                    startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -600)),
                    tokens: 45_000, requests: 3,
                    inputTokens: 32_000, outputTokens: 13_000, costSpent: 0.85,
                    modelBreakdown: [
                        ModelUsage(model: "claude-sonnet-4-20250514", inputTokens: 22_000, outputTokens: 9_000, costSpent: 0.62, requests: 2),
                        ModelUsage(model: "claude-opus-4-20250514", inputTokens: 10_000, outputTokens: 4_000, costSpent: 0.23, requests: 1)
                    ]
                )
            ),
            "minimax": Service(
                label: "MiniMax",
                quotas: [
                    Quota(type: .money, total: 20.0, used: 5.50, unit: "USD", resetsAt: nil),
                    Quota(type: .monthlyTokens, total: 3_000_000, used: 850_000, unit: "tokens", resetsAt: nil)
                ],
                currentSession: SessionSnapshot(
                    id: "minimax-preview",
                    startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -1200)),
                    tokens: 15_000, requests: 4,
                    inputTokens: 10_000, outputTokens: 5_000, costSpent: 0.08
                )
            ),
            "mimo": Service(
                label: "MiMo",
                quotas: [
                    Quota(type: .money, total: 15.0, used: 2.80, unit: "USD", resetsAt: nil),
                    Quota(type: .dailyTokens, total: 500_000, used: 120_000, unit: "tokens",
                          resetsAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 43200)))
                ],
                currentSession: SessionSnapshot(
                    id: "mimo-preview",
                    startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -800)),
                    tokens: 8_500, requests: 3,
                    inputTokens: 6_000, outputTokens: 2_500, costSpent: 0.04
                )
            )
        ]
    )
}

public enum MiniMaxTokenPlanParser {
    public static func service(from data: Data, now: Date = Date()) -> Service? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        // MiniMax wraps successful responses in { base_resp: { status_code: 0 }, data: { ... } }.
        let target: Any
        if let dict = root as? [String: Any], let dataObj = dict["data"] {
            target = dataObj
        } else {
            target = root
        }

        let quotas = quotaRecords(in: target)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .reduce(into: [Quota]()) { result, record in
                guard
                    let total = record.total,
                    total > 0,
                    let used = record.used(total: total)
                else { return }

                let type = quotaType(for: record)
                let unit = quotaUnit(for: type)
                result.append(Quota(
                    type: type,
                    total: total,
                    used: max(0, min(total, used)),
                    unit: unit,
                    resetsAt: record.resetString
                ))
            }

        guard !quotas.isEmpty else { return nil }

        let requests = quotas
            .filter { $0.unit == "requests" }
            .map(\.used)
            .reduce(0, +)

        return Service(
            label: "MiniMax",
            quotas: quotas,
            currentSession: SessionSnapshot(
                id: "minimax-token-plan",
                startedAt: ISO8601DateFormatter().string(from: now),
                tokens: nil,
                time: nil,
                money: nil,
                requests: requests > 0 ? requests : nil
            ),
            error: nil
        )
    }

    private struct QuotaRecord {
        let path: String
        let values: [String: Any]

        var total: Double? {
            firstNumber([
                "total", "total_quota", "totalQuota", "quota", "quota_limit",
                "quotaLimit", "limit", "max", "maximum"
            ])
        }

        var remaining: Double? {
            firstNumber([
                "remaining", "remain", "remains", "left", "available",
                "available_quota", "availableQuota", "unused"
            ])
        }

        var resetString: String? {
            for key in ["resets_at", "resetsAt", "reset_at", "resetAt", "expire_at", "expireAt"] {
                if let text = values[key] as? String, !text.isEmpty {
                    return normalizedDateString(text)
                }
                if let timestamp = numberValue(values[key]) {
                    return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
                }
            }
            return nil
        }

        func used(total: Double) -> Double? {
            if let used = firstNumber(["used", "usage", "consumed", "used_quota", "usedQuota"]) {
                return used
            }
            if let remaining {
                return total - remaining
            }
            return nil
        }

        private func firstNumber(_ keys: [String]) -> Double? {
            for key in keys {
                if let number = Self.numberValue(values[key]) { return number }
            }
            return nil
        }

        private static func numberValue(_ value: Any?) -> Double? {
            switch value {
            case let value as Double: return value
            case let value as Int: return Double(value)
            case let value as NSNumber: return value.doubleValue
            case let value as String:
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            default:
                return nil
            }
        }

        private func numberValue(_ value: Any?) -> Double? {
            Self.numberValue(value)
        }

        private func normalizedDateString(_ value: String) -> String {
            if ISO8601DateFormatter().date(from: value) != nil { return value }
            if let timestamp = Double(value) {
                return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
            }
            return value
        }
    }

    private static func quotaRecords(in value: Any, path: String = "") -> [QuotaRecord] {
        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, item in
                quotaRecords(in: item, path: "\(path)/\(index)")
            }
        }

        guard let dict = value as? [String: Any] else { return [] }

        let hasTotal = QuotaRecord(path: path, values: dict).total != nil
        let hasUsage = QuotaRecord(path: path, values: dict).remaining != nil ||
            QuotaRecord(path: path, values: dict).used(total: 1) != nil
        let current = hasTotal && hasUsage ? [QuotaRecord(path: path, values: dict)] : []

        let children = dict.flatMap { key, child in
            quotaRecords(in: child, path: path.isEmpty ? key : "\(path)/\(key)")
        }
        return current + children
    }

    private static func quotaType(for record: QuotaRecord) -> QuotaType {
        let haystack = (record.path + " " + record.values.keys.joined(separator: " ")).lowercased()
        if haystack.contains("token") { return haystack.contains("daily") ? .dailyTokens : .monthlyTokens }
        if haystack.contains("request") || haystack.contains("m2") || haystack.contains("text") {
            return haystack.contains("daily") ? .dailyRequests : .requests
        }
        if haystack.contains("cost") || haystack.contains("spent") { return .costSpent }
        if haystack.contains("balance") || haystack.contains("money") || haystack.contains("credit")
            || haystack.contains("amount") || haystack.contains("cash") { return .money }
        return .requests
    }

    private static func quotaUnit(for type: QuotaType) -> String {
        switch type {
        case .tokens, .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens:
            return "tokens"
        case .money, .costSpent:
            return "USD"
        case .time:
            return "seconds"
        case .requests, .dailyRequests, .monthlyRequests:
            return "requests"
        }
    }
}

public enum MiMoTokenPlanParser {
    public static func service(usageData: Data, detailData: Data?, now: Date = Date()) -> Service? {
        guard
            let usageRoot = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any],
            (usageRoot["code"] as? Int) == 0,
            let usageDataObject = usageRoot["data"] as? [String: Any],
            let usage = usageDataObject["usage"] as? [String: Any],
            let items = usage["items"] as? [[String: Any]]
        else { return nil }

        guard
            let planItem = items.first(where: { ($0["name"] as? String) == "plan_total_token" }),
            let used = numberValue(planItem["used"]),
            let limit = numberValue(planItem["limit"]),
            limit > 0
        else { return nil }

        let detail = parseDetail(detailData)
        let planName = detail.planName.map { " \($0)" } ?? ""

        return Service(
            label: "MiMo\(planName)",
            quotas: [
                Quota(
                    type: .monthlyTokens,
                    total: limit,
                    used: max(0, min(limit, used)),
                    unit: "credits",
                    resetsAt: detail.currentPeriodEnd
                )
            ],
            currentSession: SessionSnapshot(
                id: "mimo-token-plan",
                startedAt: ISO8601DateFormatter().string(from: now),
                tokens: used,
                time: nil,
                money: nil,
                requests: nil
            ),
            error: nil
        )
    }

    private static func parseDetail(_ data: Data?) -> (planName: String?, currentPeriodEnd: String?) {
        guard
            let data,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (root["code"] as? Int) == 0,
            let detail = root["data"] as? [String: Any]
        else { return (nil, nil) }

        let planName = detail["planName"] as? String
        let periodEnd = (detail["currentPeriodEnd"] as? String).flatMap(normalizedDateString)
        return (planName, periodEnd)
    }

    private static func numberValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func normalizedDateString(_ value: String) -> String? {
        if ISO8601DateFormatter().date(from: value) != nil { return value }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: value) {
            return ISO8601DateFormatter().string(from: date)
        }

        return nil
    }
}

public enum MiMoCookieHeaderBuilder {
    public static func header(from cookies: [HTTPCookie], for url: URL) -> String {
        let validCookies = cookies.filter { cookie in
            guard matches(cookie: cookie, url: url) else { return false }
            if let expiresDate = cookie.expiresDate, expiresDate <= Date() { return false }
            return true
        }

        let deduped = Dictionary(grouping: validCookies, by: \.name).compactMap { _, cookies in
            cookies.sorted(by: isMoreSpecific).first
        }

        return deduped
            .sorted(by: isMoreSpecific)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    private static func matches(cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if cookie.isSecure, url.scheme?.lowercased() != "https" { return false }

        let domain = cookie.domain.lowercased()
        let normalizedDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let domainMatches = host == normalizedDomain || host.hasSuffix(".\(normalizedDomain)")
        guard domainMatches else { return false }

        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        guard requestPath == cookiePath || requestPath.hasPrefix(cookiePath) else { return false }
        if cookiePath != "/", requestPath.count > cookiePath.count {
            let index = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
            guard requestPath[index] == "/" else { return false }
        }
        return true
    }

    private static func isMoreSpecific(_ lhs: HTTPCookie, than rhs: HTTPCookie) -> Bool {
        let lhsDomain = lhs.domain.hasPrefix(".") ? String(lhs.domain.dropFirst()) : lhs.domain
        let rhsDomain = rhs.domain.hasPrefix(".") ? String(rhs.domain.dropFirst()) : rhs.domain
        if lhsDomain.count != rhsDomain.count {
            return lhsDomain.count > rhsDomain.count
        }
        if lhs.path.count != rhs.path.count {
            return lhs.path.count > rhs.path.count
        }
        return lhs.name < rhs.name
    }
}
