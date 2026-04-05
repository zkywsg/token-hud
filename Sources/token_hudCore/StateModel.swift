// Sources/token_hudCore/StateModel.swift
import Foundation

public enum QuotaType: String, Codable, Sendable {
    case time, tokens, money, requests
}

public struct Quota: Codable, Sendable {
    public let type: QuotaType
    public let total: Double
    public let used: Double
    public let unit: String
    public let resetsAt: String?   // ISO 8601

    public var remaining: Double { total - used }
    public var usedFraction: Double { total > 0 ? (used / total) : 0 }
}

public struct SessionSnapshot: Codable, Sendable {
    public let id: String
    public let startedAt: String   // ISO 8601
    public let tokens: Double?
    public let time: Double?
    public let money: Double?
    public let requests: Double?
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
                    tokens: 45_000, time: 3600, money: 0.54, requests: 12
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
                    Quota(type: .money, total: 120.0, used: 4.20, unit: "USD", resetsAt: nil)
                ],
                currentSession: SessionSnapshot(
                    id: "codex-preview",
                    startedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -86400)),
                    tokens: 42_000, time: nil, money: 4.20, requests: nil
                )
            )
        ]
    )
}
