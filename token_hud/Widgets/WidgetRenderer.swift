// token_hud/Widgets/WidgetRenderer.swift
import SwiftUI

struct WidgetRenderer: View {
    let config: WidgetConfig
    let state: StateFile?
    var showServiceLabel: Bool = false

    @AppStorage("widgetSizeScale") private var widgetSizeScale = 1.0

    private var service: Service? { state?.services[config.service] }

    var body: some View {
        VStack(spacing: 1) {
            Group {
                switch config.style {
                case .ring:
                    RingWidget(fraction: fraction, label: formattedValue, size: 22 * widgetSizeScale)
                case .bar:
                    BarWidget(fraction: fraction, label: formattedValue, width: 60 * widgetSizeScale)
                case .text:
                    TextWidget(text: formattedValue, subtext: nil)
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

            if showServiceLabel {
                Text(service?.label ?? config.service)
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Computed values

    private var fraction: Double {
        guard let svc = service else { return 0 }
        switch config.metric {
        case .remainingTime:
            return quotaFraction(type: .time)
        case .tokensRemaining:
            return quotaFraction(type: .tokens)
        case .balance:
            return quotaFraction(type: .money)
        case .usagePercent:
            guard let q = quotaFor(type: .tokens) else { return 0 }
            return WidgetValueComputer.usageFraction(for: q)
        case .sessionTokens:
            guard let session = svc.currentSession,
                  let tokens  = session.tokens,
                  let quota   = svc.quotas.first(where: { $0.type == .tokens }),
                  let qTotal  = quota.total, qTotal > 0
            else { return 0 }
            return tokens / qTotal
        case .resetCountdown:
            guard let q = quotaFor(type: .time),
                  let resetsAt = q.resetsAt
            else { return 0 }
            let fmt = ISO8601DateFormatter()
            guard let date = fmt.date(from: resetsAt) else { return 0 }
            let remaining = date.timeIntervalSinceNow
            let total = q.total ?? 0
            return max(0, min(1, remaining / max(total, 1)))
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
        }
    }

    private var formattedValue: String {
        guard let svc = service else { return "—" }
        switch config.metric {
        case .remainingTime:
            guard let q = quotaFor(type: .time) else { return "—" }
            // Codex time quotas are rate-limit windows expressed as usage percentages.
            // Show remaining capacity as a percentage; for other services show actual time.
            if config.service == "codex" {
                let remaining = 1.0 - WidgetValueComputer.usageFraction(for: q)
                return String(format: "%.0f%%", remaining * 100)
            }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .tokensRemaining:
            guard let q = quotaFor(type: .tokens) else { return "—" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .balance:
            guard let q = quotaFor(type: .money) else { return "—" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .sessionTokens:
            return WidgetValueComputer.formattedSessionTokens(svc.currentSession)
        case .usagePercent:
            guard let q = quotaFor(type: .tokens) else { return "—" }
            return String(format: "%.0f%%", WidgetValueComputer.usageFraction(for: q) * 100)
        case .resetCountdown:
            guard let q = quotaFor(type: .time),
                  let r = q.resetsAt,
                  let s = WidgetValueComputer.countdownString(to: r)
            else { return "—" }
            return s
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
        }
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
        }
    }

    private var tooltipText: String {
        "\(service?.label ?? config.service) · \(config.metric.rawValue)"
    }

    // MARK: - Helpers

    private func quotaFor(type: QuotaType) -> Quota? {
        let matching = service?.quotas.filter { $0.type == type } ?? []
        let idx = config.quotaIndex
        return idx < matching.count ? matching[idx] : matching.first
    }

    private func quotaFraction(type: QuotaType) -> Double {
        guard let q = quotaFor(type: type) else { return 0 }
        return WidgetValueComputer.usageFraction(for: q)
    }
}
