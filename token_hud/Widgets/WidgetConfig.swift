// token_hud/Widgets/WidgetConfig.swift
import Foundation

public enum WidgetMetric: String, Codable, CaseIterable, Sendable {
    case remainingTime    = "remaining_time"
    case resetCountdown   = "reset_countdown"
    case tokensRemaining  = "tokens_remaining"
    case balance          = "balance"
    case sessionTokens    = "session_tokens"
    case usagePercent     = "usage_percent"
}

public enum WidgetStyle: String, Codable, CaseIterable, Sendable {
    case ring, bar, text, aggregate
}

public struct WidgetConfig: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var service: String
    public var metric: WidgetMetric
    public var style: WidgetStyle

    public init(id: UUID = UUID(), service: String, metric: WidgetMetric, style: WidgetStyle) {
        self.id = id; self.service = service; self.metric = metric; self.style = style
    }
}
