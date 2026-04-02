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
}

public struct StateFile: Codable, Sendable {
    public let version: Int
    public let updatedAt: String
    public let services: [String: Service]
}
