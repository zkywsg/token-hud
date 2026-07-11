// token_hud/Widgets/WidgetRenderer.swift
import SwiftUI

struct WidgetRenderer: View {
    let config: WidgetConfig
    let state: StateFile?
    var showServiceLabel: Bool = false

    @AppStorage("widgetSizeScale") private var widgetSizeScale = 1.0
    @Environment(\.panelAdaptiveScale) private var adaptiveScale

    private var service: Service? { state?.services[config.service] }
    private var metric: WidgetMetricComputer { WidgetMetricComputer(config: config, state: state) }

    private var effectiveScale: CGFloat { widgetSizeScale * adaptiveScale }

    var body: some View {
        VStack(spacing: 1 * adaptiveScale) {
            Group {
                switch config.style {
                case .ring:
                    RingWidget(fraction: fraction, label: formattedValue, size: 22 * effectiveScale, service: config.service)
                case .bar:
                    BarWidget(
                        fraction: fraction,
                        label: formattedValue,
                        detail: formattedDetail,
                        width: 60 * effectiveScale,
                        service: config.service
                    )
                case .text:
                    TextWidget(text: formattedValue, subtext: formattedDetail)
                case .aggregate:
                    AggregateWidget(icon: icon, value: formattedValue, service: config.service)
                case .multi:
                    MultiWidget(service: service, config: config, state: state)
                case .countdown:
                    CountdownWidget(fraction: fraction, label: formattedValue, service: config.service)
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

    // MARK: - Computed values (delegated to WidgetMetricComputer)

    private var fraction: Double { metric.fraction }
    private var formattedValue: String { metric.formattedValue }
    private var formattedDetail: String? { metric.formattedDetail }
    private var icon: String { metric.icon }

    private var tooltipText: String {
        "\(service?.label ?? config.service) · \(config.metric.displayName)"
    }

    private var widgetCaption: String {
        guard showServiceLabel else { return metricTitle }
        return "\(service?.label ?? config.service) · \(metricTitle)"
    }

    private var metricTitle: String { metric.metricTitle }
}
