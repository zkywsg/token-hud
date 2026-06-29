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
        WidgetMetricComputer.fraction(
            metric: config.metric, service: service,
            quotaFor: { [self] in quotaFor(type: $0) },
            creditQuota: { [self] in creditQuota() },
            quotaFraction: { [self] in quotaFraction(type: $0) }
        )
    }

    private var formattedValue: String {
        WidgetMetricComputer.formattedValue(
            metric: config.metric, service: service, configService: config.service,
            quotaFor: { [self] in quotaFor(type: $0) },
            creditQuota: { [self] in creditQuota() }
        )
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
