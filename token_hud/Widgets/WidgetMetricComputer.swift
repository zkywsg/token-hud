// token_hud/Widgets/WidgetMetricComputer.swift
import SwiftUI

/// Single source of truth for turning a `WidgetConfig` + `StateFile` into the
/// display primitives (fraction, formatted value/detail, icon) shared by
/// `WidgetRenderer` (compact chips) and `OverlayListView` (big-number rows).
struct WidgetMetricComputer {
    let config: WidgetConfig
    let state: StateFile?

    private var service: Service? { state?.services[config.service] }

    // MARK: - Presentation

    /// Decides at runtime whether this metric can be drawn as a gauge. A gauge
    /// requires a real `quota.total`; without one the value is an unbounded
    /// counter and must not be shown as a proportion.
    var presentation: MetricPresentation {
        switch config.metric {
        case .subscriptionStatus, .planName, .resetCountdown:
            return .status
        case .remainingTime:
            return hasTotal(for: .time) ? .quota(fraction) : .counter
        case .sessionTokens, .inputTokens, .outputTokens:
            return hasTotal(for: .tokens) ? .quota(fraction) : .counter
        case .costSpent:
            return hasTotal(for: .money) ? .quota(fraction) : .counter
        case .sessionCredits:
            return creditQuota()?.total.map { $0 > 0 } == true ? .quota(fraction) : .counter
        case .sessionDuration, .tokensPerMinute, .inputOutputRatio, .costPerRequest:
            // Retired: their percentages came from hardcoded denominators.
            return .counter
        default:
            return .quota(fraction)
        }
    }

    private func hasTotal(for type: QuotaType) -> Bool {
        guard let total = service?.quotas.first(where: { $0.type == type })?.total else { return false }
        return total > 0
    }

    // MARK: - Fraction (0...1, usage)

    var fraction: Double {
        guard let svc = service else { return 0 }
        switch config.metric {
        case .remainingTime:
            // Only a real time quota has a denominator. The credit-quota
            // fallback is a countdown to a date, which used to be divided by a
            // hardcoded 30 days — that percentage meant nothing, so it's gone.
            guard let q = quotaFor(type: .time), q.type == .time else { return 0 }
            return quotaFraction(type: .time)
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
            // A timestamp, not a magnitude — rendered as a label.
            return 0
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
        // Retired metrics: these previously divided by hardcoded constants
        // (8h session, 200 tokens/min) to fake a percentage. They render as
        // plain counters now, so they contribute no fraction.
        case .sessionDuration, .tokensPerMinute, .inputOutputRatio, .costPerRequest:
            return 0
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

    // MARK: - Formatted value

    var formattedValue: String {
        guard let svc = service else { return "—" }
        switch config.metric {
        case .remainingTime:
            if config.service == "mimo" {
                return WidgetValueComputer.formattedMiMoTokenPlanExpiry(service)
            }
            guard let q = quotaFor(type: .time) ?? creditQuota() else { return "—" }
            if config.service == "codex" {
                return WidgetValueComputer.codexRateLimitDisplay(q).value
            }
            if q.type == .time {
                return WidgetValueComputer.formattedRemaining(quota: q)
            }
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

    var formattedDetail: String? {
        guard config.service == "codex",
              config.metric == .remainingTime,
              let q = quotaFor(type: .time)
        else { return nil }
        return WidgetValueComputer.codexRateLimitDisplay(q).detail
    }

    var icon: String {
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

    var metricTitle: String {
        if config.service == "codex", config.metric == .remainingTime {
            // Derived from the quota's real duration — Codex removed its
            // 5-hour window, so a hardcoded index→name map lies.
            return WidgetValueComputer.rateLimitWindowDisplayName(quotaFor(type: .time))
        }
        if config.service == "mimo", config.metric == .resetCountdown {
            return "Token Plan 到期时间"
        }
        if config.service == "mimo", config.metric == .remainingTime {
            return "Token Plan 到期时间"
        }
        return config.metric.displayName
    }

    var serviceLabel: String { service?.label ?? config.service }

    // MARK: - Helpers

    private func quotaFor(type: QuotaType) -> Quota? {
        let matching = service?.quotas.filter { $0.type == type } ?? []
        let idx = config.quotaIndex
        return idx < matching.count ? matching[idx] : matching.first
    }

    private func creditQuota() -> Quota? {
        service?.quotas.first { $0.unit.lowercased() == "credits" }
    }

    private func quotaFraction(type: QuotaType) -> Double {
        guard let q = quotaFor(type: type) else { return 0 }
        return WidgetValueComputer.usageFraction(for: q)
    }
}
