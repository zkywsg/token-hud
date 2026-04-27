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
            )
        ]
    )
}
