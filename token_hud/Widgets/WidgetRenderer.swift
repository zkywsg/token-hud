// token_hud/Widgets/WidgetRenderer.swift
import SwiftUI

struct WidgetRenderer: View {
    let config: WidgetConfig
    let state: StateFile?

    private var service: Service? { state?.services[config.service] }

    var body: some View {
        Group {
            switch config.style {
            case .ring:
                RingWidget(fraction: fraction, label: formattedValue, size: 30)
            case .bar:
                BarWidget(fraction: fraction, label: formattedValue, width: 60)
            case .text:
                TextWidget(text: formattedValue, subtext: nil)
            case .aggregate:
                AggregateWidget(icon: icon, value: formattedValue)
            }
        }
        .help(tooltipText)
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
                  quota.total > 0
            else { return 0 }
            return tokens / quota.total
        case .resetCountdown:
            guard let q = quotaFor(type: .time),
                  let resetsAt = q.resetsAt
            else { return 0 }
            let fmt = ISO8601DateFormatter()
            guard let date = fmt.date(from: resetsAt) else { return 0 }
            let remaining = date.timeIntervalSinceNow
            let total = q.total
            return max(0, min(1, remaining / max(total, 1)))
        }
    }

    private var formattedValue: String {
        guard let svc = service else { return "—" }
        switch config.metric {
        case .remainingTime:
            guard let q = quotaFor(type: .time) else { return "—" }
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
        }
    }

    private var tooltipText: String {
        "\(service?.label ?? config.service) · \(config.metric.rawValue)"
    }

    // MARK: - Helpers

    private func quotaFor(type: QuotaType) -> Quota? {
        service?.quotas.first { $0.type == type }
    }

    private func quotaFraction(type: QuotaType) -> Double {
        guard let q = quotaFor(type: type) else { return 0 }
        return WidgetValueComputer.usageFraction(for: q)
    }
}
