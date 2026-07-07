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
                    AggregateWidget(icon: config.metric.icon, value: formattedValue)
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

    private var tooltipText: String {
        WidgetMetricComputer.tooltipText(
            metric: config.metric, service: service, configService: config.service,
            metricTitle: config.metric.displayName
        )
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
        return config.metric.baseTitle(for: config.service)
    }

    private func quotaFraction(type: QuotaType) -> Double {
        guard let q = quotaFor(type: type) else { return 0 }
        return WidgetValueComputer.usageFraction(for: q)
    }
}
