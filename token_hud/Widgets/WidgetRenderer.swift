// token_hud/Widgets/WidgetRenderer.swift
import SwiftUI

struct WidgetRenderer: View {
    let config: WidgetConfig
    let state: StateFile?
    var showServiceLabel: Bool = false

    @AppStorage("widgetSizeScale") private var widgetSizeScale = 1.0
    @Environment(\.panelAdaptiveScale) private var adaptiveScale

    private var service: Service? { state?.services[config.service] }

    private var effectiveScale: CGFloat { widgetSizeScale * adaptiveScale }

    var body: some View {
        VStack(spacing: 1 * adaptiveScale) {
            Group {
                switch config.style {
                case .ring:
                    RingWidget(fraction: fraction, label: formattedValue, size: 22 * effectiveScale)
                case .bar:
                    BarWidget(
                        fraction: fraction,
                        label: formattedValue,
                        detail: formattedDetail,
                        width: 60 * effectiveScale
                    )
                case .text:
                    TextWidget(text: formattedValue, subtext: formattedDetail)
                case .aggregate:
                    AggregateWidget(icon: icon, value: formattedValue)
                case .multi:
                    MultiWidget(service: service, config: config, state: state)
                case .countdown:
                    CountdownWidget(fraction: fraction, label: formattedValue)
                case .status:
                    StatusWidget(fraction: fraction, label: formattedValue)
                case .modelBreakdown:
                    ModelBreakdownWidget(service: service)
                }
            }
            .help(tooltipText)

            if !widgetCaption.isEmpty {
                Text(widgetCaption)
                    .font(.system(size: 8 * adaptiveScale, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
    }

    // MARK: - Computed values

    private var fraction: Double {
        guard let svc = service else { return 0 }
        switch config.metric {
        case .remainingTime:
            guard let q = quotaFor(type: .time) ?? creditQuota() else { return 0 }
            if q.type == .time { return quotaFraction(type: .time) }
            guard let resetsAt = q.resetsAt,
                  let date = ISO8601DateFormatter().date(from: resetsAt)
            else { return 0 }
            return max(0, min(1, date.timeIntervalSinceNow / 2_592_000))
        case .tokensRemaining:
            return quotaFraction(type: .tokens)
        case .balance:
            return quotaFraction(type: .money)
        case .usagePercent:
            guard let q = quotaFor(type: .tokens) ?? creditQuota() else { return 0 }
            return WidgetValueComputer.usageFraction(for: q)
        case .sessionTokens:
            guard let session = svc.currentSession,
                  let tokens  = session.tokens,
                  let quota   = svc.quotas.first(where: { $0.type == .tokens }),
                  let qTotal  = quota.total, qTotal > 0
            else { return 0 }
            return tokens / qTotal
        case .resetCountdown:
            guard let q = quotaFor(type: .time) ?? creditQuota(),
                  let resetsAt = q.resetsAt,
                  let date = ISO8601DateFormatter().date(from: resetsAt)
            else { return 0 }
            let remaining = date.timeIntervalSinceNow
            let maxSeconds = q.type == .time ? max(q.total ?? 0, 1) : 2_592_000.0 // 30 days for credit quotas
            return max(0, min(1, remaining / maxSeconds))
        case .inputTokens:
            guard let val = svc.currentSession?.inputTokens,
                  let quota = svc.quotas.first(where: { $0.type == .tokens }),
                  let total = quota.total, total > 0
            else { return 0 }
            return val / total
        case .outputTokens:
            guard let val = svc.currentSession?.outputTokens,
                  let quota = svc.quotas.first(where: { $0.type == .tokens }),
                  let total = quota.total, total > 0
            else { return 0 }
            return val / total
        case .dailyTokens:
            return quotaFraction(type: .dailyTokens)
        case .monthlyTokens:
            return quotaFraction(type: .monthlyTokens)
        case .costSpent:
            guard let val = svc.currentSession?.costSpent,
                  let quota = svc.quotas.first(where: { $0.type == .money }),
                  let total = quota.total, total > 0
            else { return 0 }
            return val / total
        case .dailyRequests:
            return quotaFraction(type: .dailyRequests)
        case .monthlyRequests:
            return quotaFraction(type: .monthlyRequests)
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
            let fractions = svc.quotas.compactMap { q -> Double? in
                guard q.total != nil, q.total! > 0 else { return nil }
                return q.used / q.total!
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
                  let total = q.total,
                  total > 0
            else { return 0 }
            return sessionCredits / total
        case .subscriptionStatus:
            return svc.error == nil ? 1 : 0
        case .planName:
            return 0
        }
    }

    private var formattedValue: String {
        guard let svc = service else { return "—" }
        switch config.metric {
        case .remainingTime:
            if config.service == "mimo" {
                return WidgetValueComputer.formattedMiMoTokenPlanExpiry(service)
            }
            guard let q = quotaFor(type: .time) ?? creditQuota() else { return "—" }
            // Codex time quotas are rate-limit windows expressed as usage percentages.
            // Show remaining capacity as a percentage; for other services show actual time.
            if config.service == "codex" {
                return WidgetValueComputer.codexRateLimitDisplay(q).value
            }
            if q.type == .time {
                return WidgetValueComputer.formattedRemaining(quota: q)
            }
            // For credit-based quotas (e.g. MiMo), show countdown to reset
            guard let resetsAt = q.resetsAt else { return "—" }
            return WidgetValueComputer.countdownString(to: resetsAt) ?? "—"
        case .tokensRemaining:
            guard let q = quotaFor(type: .tokens) else { return "—" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .balance:
            guard let q = quotaFor(type: .money) else { return "—" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .sessionTokens:
            return WidgetValueComputer.formattedSessionTokens(svc.currentSession)
        case .usagePercent:
            guard let q = quotaFor(type: .tokens) ?? creditQuota() else { return "—" }
            return String(format: "%.0f%%", WidgetValueComputer.usageFraction(for: q) * 100)
        case .resetCountdown:
            if config.service == "mimo" {
                return WidgetValueComputer.formattedMiMoTokenPlanExpiry(service)
            }
            guard let q = quotaFor(type: .time) ?? creditQuota(),
                  let r = q.resetsAt
            else { return "—" }
            let fmt = ISO8601DateFormatter()
            guard let date = fmt.date(from: r) else { return r }
            let df = DateFormatter()
            df.dateFormat = "MM/dd HH:mm"
            return df.string(from: date)
        case .inputTokens:
            return WidgetValueComputer.formattedInputTokens(svc.currentSession)
        case .outputTokens:
            return WidgetValueComputer.formattedOutputTokens(svc.currentSession)
        case .costSpent:
            return WidgetValueComputer.formattedCostSpent(svc.currentSession)
        case .dailyTokens:
            guard let q = quotaFor(type: .dailyTokens) else { return "—" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .monthlyTokens:
            guard let q = quotaFor(type: .monthlyTokens) else { return "—" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .dailyRequests:
            guard let q = quotaFor(type: .dailyRequests) else { return "—" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .monthlyRequests:
            guard let q = quotaFor(type: .monthlyRequests) else { return "—" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .sessionDuration:
            guard let session = svc.currentSession else { return "—" }
            return WidgetValueComputer.sessionDuration(from: session)
        case .tokensPerMinute:
            guard let session = svc.currentSession else { return "—" }
            return WidgetValueComputer.tokensPerMinute(from: session)
        case .inputOutputRatio:
            guard let session = svc.currentSession else { return "—" }
            return WidgetValueComputer.inputOutputRatio(from: session)
        case .costPerRequest:
            guard let session = svc.currentSession else { return "—" }
            return WidgetValueComputer.costPerRequest(from: session)
        case .rateLimitStatus:
            let fractions = svc.quotas.compactMap { q -> Double? in
                guard let t = q.total, t > 0 else { return nil }
                return q.used / t
            }
            guard let max = fractions.max() else { return "—" }
            return String(format: "%.0f%%", max * 100)
        case .creditsRemaining:
            guard let q = creditQuota() else { return "—" }
            return WidgetValueComputer.formattedCredits(WidgetValueComputer.remainingValue(for: q))
        case .creditsUsed:
            guard let q = creditQuota() else { return "—" }
            return WidgetValueComputer.formattedCredits(q.used)
        case .sessionCredits:
            return WidgetValueComputer.formattedCredits(svc.currentSession?.tokens)
        case .subscriptionStatus:
            if config.service == "codex" {
                return WidgetValueComputer.codexSubscriptionStatus(svc)
            }
            if svc.error != nil { return "异常" }
            return svc.currentSession == nil && svc.quotas.isEmpty ? "未连接" : "已订阅"
        case .planName:
            return service?.label ?? config.service
        }
    }

    private var formattedDetail: String? {
        guard config.service == "codex",
              config.metric == .remainingTime,
              let q = quotaFor(type: .time)
        else { return nil }
        return WidgetValueComputer.codexRateLimitDisplay(q).detail
    }

    private var icon: String {
        switch config.metric {
        case .remainingTime:   return "clock"
        case .resetCountdown:  return "arrow.clockwise"
        case .tokensRemaining: return "text.bubble"
        case .balance:         return "dollarsign.circle"
        case .sessionTokens:   return "arrow.up.circle"
        case .usagePercent:    return "chart.bar"
        case .inputTokens:     return "arrow.down.circle"
        case .outputTokens:    return "arrow.up.circle"
        case .dailyTokens:     return "calendar"
        case .monthlyTokens:   return "calendar.circle"
        case .costSpent:       return "dollarsign.circle.fill"
        case .dailyRequests:   return "number.circle"
        case .monthlyRequests: return "number.circle.fill"
        case .sessionDuration:   return "timer"
        case .tokensPerMinute:   return "bolt.fill"
        case .inputOutputRatio:  return "arrow.left.arrow.right"
        case .costPerRequest:    return "dollarsign.arrow.circlepath"
        case .rateLimitStatus:   return "exclamationmark.triangle"
        case .creditsRemaining:  return "creditcard"
        case .creditsUsed:       return "chart.pie"
        case .sessionCredits:    return "sum"
        case .subscriptionStatus:return "checkmark.seal"
        case .planName:          return "tag"
        }
    }

    private var tooltipText: String {
        "\(service?.label ?? config.service) · \(config.metric.displayName)"
    }

    private var widgetCaption: String {
        guard showServiceLabel else { return metricTitle }
        return "\(service?.label ?? config.service) · \(metricTitle)"
    }

    // MARK: - Helpers

    private func quotaFor(type: QuotaType) -> Quota? {
        let matching = service?.quotas.filter { $0.type == type } ?? []
        let idx = config.quotaIndex
        return idx < matching.count ? matching[idx] : matching.first
    }

    private func creditQuota() -> Quota? {
        service?.quotas.first { $0.unit.lowercased() == "credits" }
    }

    private var metricTitle: String {
        if config.service == "codex", config.metric == .remainingTime {
            return ""
        }
        if config.service == "mimo", config.metric == .resetCountdown {
            return "Token Plan 到期时间"
        }
        if config.service == "mimo", config.metric == .remainingTime {
            return "Token Plan 到期时间"
        }
        return config.metric.displayName
    }

    private func quotaFraction(type: QuotaType) -> Double {
        guard let q = quotaFor(type: type) else { return 0 }
        return WidgetValueComputer.usageFraction(for: q)
    }
}
