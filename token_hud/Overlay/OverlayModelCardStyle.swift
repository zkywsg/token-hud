import SwiftUI

enum OverlayModelCardStyle {
    static func cardCornerRadius(scale: CGFloat) -> CGFloat {
        max(10, 13 * scale)
    }

    static func innerCornerRadius(scale: CGFloat) -> CGFloat {
        max(8, 10 * scale)
    }

    static func cardSpacing(scale: CGFloat) -> CGFloat {
        max(7, 8 * scale)
    }

    static func cardPadding(scale: CGFloat) -> CGFloat {
        max(8, 9 * scale)
    }

    static func widgetSpacing(scale: CGFloat) -> CGFloat {
        max(6, 7 * scale)
    }

    static func serviceCardMinWidth(scale: CGFloat) -> CGFloat {
        max(218, 238 * scale)
    }

    static func serviceCardMaxWidth(scale: CGFloat) -> CGFloat {
        max(serviceCardMinWidth(scale: scale), 276 * scale)
    }

    static func metricTileMinWidth(scale: CGFloat) -> CGFloat {
        max(92, 104 * scale)
    }

    static func metricTileMaxWidth(scale: CGFloat) -> CGFloat {
        max(118, 136 * scale)
    }

    static func hostedBodyTopInset(scale: CGFloat) -> CGFloat {
        max(14, 16 * scale)
    }
}

struct OverlayModelCard<Accessory: View, Content: View>: View {
    let serviceLabel: String
    let componentCount: Int
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    @Environment(\.panelAdaptiveScale) private var scale

    init(
        serviceLabel: String,
        componentCount: Int,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.serviceLabel = serviceLabel
        self.componentCount = componentCount
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OverlayModelCardStyle.cardSpacing(scale: scale)) {
            HStack(spacing: 7 * scale) {
                Text(serviceLabel)
                    .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.64))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(componentCount)")
                    .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.34))
                    .lineLimit(1)

                Spacer(minLength: 0)

                accessory
            }

            content
        }
        .padding(OverlayModelCardStyle.cardPadding(scale: scale))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: OverlayModelCardStyle.cardCornerRadius(scale: scale), style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OverlayModelCardStyle.cardCornerRadius(scale: scale), style: .continuous)
                .stroke(Color.white.opacity(0.085), lineWidth: max(0.5, 0.6 * scale))
        )
    }
}

struct OverlayServiceCardGrid<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.panelAdaptiveScale) private var scale

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var spacing: CGFloat {
        OverlayModelCardStyle.cardSpacing(scale: scale)
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: OverlayModelCardStyle.serviceCardMinWidth(scale: scale),
                    maximum: OverlayModelCardStyle.serviceCardMaxWidth(scale: scale)
                ),
                spacing: spacing,
                alignment: .top
            )
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct OverlayMetricGrid: View {
    let widgets: [WidgetConfig]
    let state: StateFile?

    @Environment(\.panelAdaptiveScale) private var scale

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: OverlayModelCardStyle.metricTileMinWidth(scale: scale),
                    maximum: OverlayModelCardStyle.metricTileMaxWidth(scale: scale)
                ),
                spacing: OverlayModelCardStyle.widgetSpacing(scale: scale),
                alignment: .topLeading
            )
        ]
    }

    var body: some View {
        if widgets.count == 1, let config = widgets.first {
            OverlayMetricTile(config: config, state: state)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: OverlayModelCardStyle.widgetSpacing(scale: scale)) {
                ForEach(widgets) { config in
                    OverlayMetricTile(config: config, state: state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct OverlayMetricTile: View {
    let config: WidgetConfig
    let state: StateFile?

    @Environment(\.panelAdaptiveScale) private var scale

    private var service: Service? { state?.services[config.service] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(spacing: 6 * scale) {
                Text(formattedValue)
                    .font(.system(size: 12.5 * scale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(HUDTextStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)
            }

            if showsProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(progressColor)
                            .frame(width: geo.size.width * CGFloat(progressFraction.clamped(to: 0...1)))
                    }
                }
                .frame(height: max(3.5, 4 * scale))
            }

            Text(metricTitle)
                .font(.system(size: 8.8 * scale, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.52))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, max(8, 9 * scale))
        .padding(.vertical, max(7, 8 * scale))
        .frame(minHeight: max(42, 46 * scale), alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: OverlayModelCardStyle.innerCornerRadius(scale: scale), style: .continuous)
                .fill(Color.white.opacity(0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OverlayModelCardStyle.innerCornerRadius(scale: scale), style: .continuous)
                .stroke(Color.white.opacity(0.065), lineWidth: max(0.5, 0.6 * scale))
        )
        .help(tooltipText)
    }

    private var showsProgress: Bool {
        switch config.style {
        case .bar, .ring, .countdown, .status:
            return true
        case .text, .aggregate, .multi, .modelBreakdown:
            return config.metric == .remainingTime || config.metric == .usagePercent || config.metric == .rateLimitStatus
        }
    }

    private var progressFraction: Double {
        switch config.metric {
        case .remainingTime:
            if config.service == "codex" {
                return 1 - fraction
            }
            return fraction
        case .tokensRemaining, .balance, .creditsRemaining:
            return 1 - fraction
        default:
            return fraction
        }
    }

    private var progressColor: Color {
        ProgressColorScheme.color(for: progressFraction)
    }

    private var formattedValue: String {
        WidgetMetricComputer.formattedValue(
            metric: config.metric, service: service, configService: config.service,
            quotaFor: { [self] in quotaFor(type: $0) },
            creditQuota: { [self] in creditQuota() }
        )
    }

    private var fraction: Double {
        WidgetMetricComputer.fraction(
            metric: config.metric, service: service,
            quotaFor: { [self] in quotaFor(type: $0) },
            creditQuota: { [self] in creditQuota() },
            quotaFraction: { [self] in quotaFraction(type: $0) }
        )
    }

    private var metricTitle: String {
        if config.service == "codex", config.metric == .remainingTime {
            guard let quota = quotaFor(type: .time) else { return config.metric.displayName }
            return WidgetValueComputer.codexRateLimitDisplay(quota).detail ?? config.metric.displayName
        }
        return config.metric.baseTitle(for: config.service)
    }

    private var tooltipText: String {
        WidgetMetricComputer.tooltipText(
            metric: config.metric, service: service, configService: config.service,
            metricTitle: metricTitle
        )
    }

    private func quotaFor(type: QuotaType) -> Quota? {
        let matching = service?.quotas.filter { $0.type == type } ?? []
        let index = config.quotaIndex
        return index < matching.count ? matching[index] : matching.first
    }

    private func creditQuota() -> Quota? {
        service?.quotas.first { $0.unit.lowercased() == "credits" }
    }

    private func quotaFraction(type: QuotaType) -> Double {
        guard let quota = quotaFor(type: type) else { return 0 }
        return WidgetValueComputer.usageFraction(for: quota)
    }
}

struct OverlayWidgetFlow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    init(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: spacing) {
                content
            }
            .padding(.horizontal, 1)
        }
    }
}
