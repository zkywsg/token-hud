// token_hud/Widgets/WidgetConfig.swift
import Foundation

public enum WidgetMetric: String, Codable, CaseIterable, Sendable {
    case remainingTime    = "remaining_time"
    case resetCountdown   = "reset_countdown"
    case tokensRemaining  = "tokens_remaining"
    case balance          = "balance"
    case sessionTokens    = "session_tokens"
    case usagePercent     = "usage_percent"
    case inputTokens      = "input_tokens"
    case outputTokens     = "output_tokens"
    case dailyTokens      = "daily_tokens"
    case monthlyTokens    = "monthly_tokens"
    case costSpent        = "cost_spent"
    case dailyRequests    = "daily_requests"
    case monthlyRequests  = "monthly_requests"
    case sessionDuration   = "session_duration"
    case tokensPerMinute   = "tokens_per_minute"
    case inputOutputRatio  = "input_output_ratio"
    case costPerRequest    = "cost_per_request"
    case rateLimitStatus   = "rate_limit_status"
    case creditsRemaining  = "credits_remaining"
    case creditsUsed       = "credits_used"
    case sessionCredits    = "session_credits"
    case subscriptionStatus = "subscription_status"
    case planName          = "plan_name"
}

public enum WidgetStyle: String, Codable, CaseIterable, Sendable {
    case ring, bar, text, aggregate, multi, countdown, status, modelBreakdown
}

public struct WidgetConfig: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var service: String
    public var metric: WidgetMetric
    public var style: WidgetStyle
    /// Which quota of the matching type to use (0 = first/primary, 1 = second/secondary, …)
    public var quotaIndex: Int

    public init(id: UUID = UUID(), service: String, metric: WidgetMetric, style: WidgetStyle, quotaIndex: Int = 0) {
        self.id = id; self.service = service; self.metric = metric; self.style = style; self.quotaIndex = quotaIndex
    }

    // Custom decoder so existing saved configs without quotaIndex default to 0
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,         forKey: .id)
        service    = try c.decode(String.self,       forKey: .service)
        metric     = try c.decode(WidgetMetric.self, forKey: .metric)
        style      = try c.decode(WidgetStyle.self,  forKey: .style)
        quotaIndex = (try? c.decode(Int.self,        forKey: .quotaIndex)) ?? 0
    }
}

extension WidgetMetric {
    public var displayName: String {
        switch self {
        case .remainingTime:   return "剩余时间"
        case .resetCountdown:  return "重置倒计时"
        case .tokensRemaining: return "剩余 Token"
        case .balance:         return "余额"
        case .sessionTokens:   return "会话 Token"
        case .usagePercent:    return "使用率"
        case .inputTokens:     return "输入 Token"
        case .outputTokens:    return "输出 Token"
        case .dailyTokens:     return "日 Token 用量"
        case .monthlyTokens:   return "月 Token 用量"
        case .costSpent:       return "已花费"
        case .dailyRequests:   return "日请求数"
        case .monthlyRequests: return "月请求数"
        case .sessionDuration:   return "会话时长"
        case .tokensPerMinute:   return "消耗速率"
        case .inputOutputRatio:  return "输入输出比"
        case .costPerRequest:    return "单次花费"
        case .rateLimitStatus:   return "限制状态"
        case .creditsRemaining:  return "剩余 Credit"
        case .creditsUsed:       return "Credit 用量"
        case .sessionCredits:    return "会话 Credit"
        case .subscriptionStatus:return "订阅状态"
        case .planName:          return "套餐名称"
        }
    }
}

extension WidgetStyle {
    public var displayName: String {
        switch self {
        case .ring:      return "圆环"
        case .bar:       return "进度条"
        case .text:      return "文字"
        case .aggregate: return "汇总"
        case .multi:          return "多指标"
        case .countdown:      return "倒计时"
        case .status:         return "状态灯"
        case .modelBreakdown: return "模型拆分"
        }
    }
}
