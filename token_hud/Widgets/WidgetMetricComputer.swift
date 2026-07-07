// token_hud/Widgets/WidgetMetricComputer.swift
import Foundation

/// Shared computation for widget metric display values and fractions.
/// Used by both `WidgetRenderer` (compact HUD) and `OverlayMetricTile` (card HUD)
/// to avoid duplicating the 22-case switch logic.
enum WidgetMetricComputer {
    // MARK: - Formatted value

    static func formattedValue(
        metric: WidgetMetric,
        service: Service?,
        configService: String,
        quotaFor: (QuotaType) -> Quota?,
        creditQuota: () -> Quota?
    ) -> String {
        guard let svc = service else { return "-" }
        switch metric {
        case .remainingTime:
            if configService == "mimo" {
                return WidgetValueComputer.formattedMiMoTokenPlanExpiry(service)
            }
            guard let q = quotaFor(.time) ?? creditQuota() else { return "-" }
            if configService == "codex" {
                return WidgetValueComputer.codexRateLimitDisplay(q).value
            }
            if q.type == .time {
                return WidgetValueComputer.formattedRemaining(quota: q)
            }
            guard let resetsAt = q.resetsAt else { return "-" }
            return WidgetValueComputer.countdownString(to: resetsAt) ?? "-"
        case .tokensRemaining:
            guard let q = quotaFor(.tokens) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .balance:
            guard let q = quotaFor(.money) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .sessionTokens:
            return WidgetValueComputer.formattedSessionTokens(svc.currentSession)
        case .usagePercent:
            guard let q = quotaFor(.tokens) ?? creditQuota() else { return "-" }
            return String(format: "%.0f%%", WidgetValueComputer.usageFraction(for: q) * 100)
        case .resetCountdown:
            if configService == "mimo" {
                return WidgetValueComputer.formattedMiMoTokenPlanExpiry(service)
            }
            guard let q = quotaFor(.time) ?? creditQuota(),
                  let resetsAt = q.resetsAt
            else { return "-" }
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: resetsAt) else { return resetsAt }
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MM/dd HH:mm"
            return displayFormatter.string(from: date)
        case .inputTokens:
            return WidgetValueComputer.formattedInputTokens(svc.currentSession)
        case .outputTokens:
            return WidgetValueComputer.formattedOutputTokens(svc.currentSession)
        case .dailyTokens:
            guard let q = quotaFor(.dailyTokens) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .monthlyTokens:
            guard let q = quotaFor(.monthlyTokens) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .costSpent:
            return WidgetValueComputer.formattedCostSpent(svc.currentSession)
        case .dailyRequests:
            guard let q = quotaFor(.dailyRequests) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .monthlyRequests:
            guard let q = quotaFor(.monthlyRequests) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .sessionDuration:
            guard let session = svc.currentSession else { return "-" }
            return WidgetValueComputer.sessionDuration(from: session)
        case .tokensPerMinute:
            guard let session = svc.currentSession else { return "-" }
            return WidgetValueComputer.tokensPerMinute(from: session)
        case .inputOutputRatio:
            guard let session = svc.currentSession else { return "-" }
            return WidgetValueComputer.inputOutputRatio(from: session)
        case .costPerRequest:
            guard let session = svc.currentSession else { return "-" }
            return WidgetValueComputer.costPerRequest(from: session)
        case .rateLimitStatus:
            let fractions = svc.quotas.compactMap { quota -> Double? in
                guard let total = quota.total, total > 0 else { return nil }
                return quota.used / total
            }
            guard let maxFraction = fractions.max() else { return "-" }
            return String(format: "%.0f%%", maxFraction * 100)
        case .creditsRemaining:
            guard let q = creditQuota() else { return "-" }
            return WidgetValueComputer.formattedCredits(WidgetValueComputer.remainingValue(for: q))
        case .creditsUsed:
            guard let q = creditQuota() else { return "-" }
            return WidgetValueComputer.formattedCredits(q.used)
        case .sessionCredits:
            return WidgetValueComputer.formattedCredits(svc.currentSession?.tokens)
        case .subscriptionStatus:
            if configService == "codex" {
                return WidgetValueComputer.codexSubscriptionStatus(svc)
            }
            if svc.error != nil { return "异常" }
            return svc.currentSession == nil && svc.quotas.isEmpty ? "未连接" : "已订阅"
        case .planName:
            return service?.label ?? configService
        }
    }

    // MARK: - Tooltip

    static func tooltipText(
        metric: WidgetMetric,
        service: Service?,
        configService: String,
        metricTitle: String
    ) -> String {
        "\(service?.label ?? configService) · \(metricTitle)"
    }

    // MARK: - Fraction (usage 0...1)

    static func fraction(
        metric: WidgetMetric,
        service: Service?,
        quotaFor: (QuotaType) -> Quota?,
        creditQuota: () -> Quota?,
        quotaFraction: (QuotaType) -> Double
    ) -> Double {
        guard let svc = service else { return 0 }
        switch metric {
        case .remainingTime:
            guard let q = quotaFor(.time) ?? creditQuota() else { return 0 }
            if q.type == .time { return quotaFraction(.time) }
            guard let resetsAt = q.resetsAt,
                  let date = ISO8601DateFormatter().date(from: resetsAt)
            else { return 0 }
            return max(0, min(1, date.timeIntervalSinceNow / 2_592_000))
        case .tokensRemaining:
            return quotaFraction(.tokens)
        case .balance:
            return quotaFraction(.money)
        case .usagePercent:
            guard let q = quotaFor(.tokens) ?? creditQuota() else { return 0 }
            return WidgetValueComputer.usageFraction(for: q)
        case .sessionTokens:
            guard let session = svc.currentSession,
                  let tokens = session.tokens,
                  let quota = svc.quotas.first(where: { $0.type == .tokens }),
                  let total = quota.total, total > 0
            else { return 0 }
            return tokens / total
        case .resetCountdown:
            guard let q = quotaFor(.time) ?? creditQuota(),
                  let resetsAt = q.resetsAt,
                  let date = ISO8601DateFormatter().date(from: resetsAt)
            else { return 0 }
            let remaining = date.timeIntervalSinceNow
            let maxSeconds = q.type == .time ? max(q.total ?? 0, 1) : 2_592_000.0
            return max(0, min(1, remaining / maxSeconds))
        case .inputTokens:
            guard let value = svc.currentSession?.inputTokens,
                  let quota = svc.quotas.first(where: { $0.type == .tokens }),
                  let total = quota.total, total > 0
            else { return 0 }
            return value / total
        case .outputTokens:
            guard let value = svc.currentSession?.outputTokens,
                  let quota = svc.quotas.first(where: { $0.type == .tokens }),
                  let total = quota.total, total > 0
            else { return 0 }
            return value / total
        case .dailyTokens:
            return quotaFraction(.dailyTokens)
        case .monthlyTokens:
            return quotaFraction(.monthlyTokens)
        case .costSpent:
            guard let value = svc.currentSession?.costSpent,
                  let quota = svc.quotas.first(where: { $0.type == .money }),
                  let total = quota.total, total > 0
            else { return 0 }
            return value / total
        case .dailyRequests:
            return quotaFraction(.dailyRequests)
        case .monthlyRequests:
            return quotaFraction(.monthlyRequests)
        case .sessionDuration:
            guard let session = svc.currentSession else { return 0 }
            return min(1, WidgetValueComputer.sessionDurationSeconds(from: session) / 28800)
        case .tokensPerMinute:
            guard let session = svc.currentSession,
                  let tokens = session.tokens,
                  WidgetValueComputer.sessionDurationSeconds(from: session) > 60
            else { return 0 }
            let rate = tokens / (WidgetValueComputer.sessionDurationSeconds(from: session) / 60)
            return min(1, rate / 200)
        case .inputOutputRatio:
            guard let input = svc.currentSession?.inputTokens,
                  let output = svc.currentSession?.outputTokens,
                  (input + output) > 0
            else { return 0 }
            return input / (input + output)
        case .costPerRequest:
            guard let cost = svc.currentSession?.costSpent,
                  let quota = svc.quotas.first(where: { $0.type == .money }),
                  let total = quota.total, total > 0
            else { return 0 }
            return cost / total
        case .rateLimitStatus:
            let fractions = svc.quotas.compactMap { quota -> Double? in
                guard let total = quota.total, total > 0 else { return nil }
                return quota.used / total
            }
            return fractions.max() ?? 0
        case .creditsRemaining:
            guard let q = creditQuota() else { return 0 }
            return WidgetValueComputer.usageFraction(for: q)
        case .creditsUsed:
            guard let q = creditQuota() else { return 0 }
            return 1 - WidgetValueComputer.usageFraction(for: q)
        case .sessionCredits:
            guard let sessionCredits = svc.currentSession?.tokens,
                  let q = creditQuota(),
                  let total = q.total, total > 0
            else { return 0 }
            return sessionCredits / total
        case .subscriptionStatus:
            return svc.error == nil ? 1 : 0
        case .planName:
            return 0
        }
    }
}
