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
                    .foregroundColor(.white.opacity(0.94))
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
        let usage = progressFraction.clamped(to: 0...1)
        if usage >= 0.85 { return Color(red: 1.0, green: 0.27, blue: 0.32) }
        if usage >= 0.65 { return Color(red: 1.0, green: 0.78, blue: 0.22) }
        return Color(red: 0.26, green: 0.82, blue: 0.50)
    }

    private var formattedValue: String {
        guard let svc = service else { return "-" }
        switch config.metric {
        case .remainingTime:
            if config.service == "mimo" {
                return WidgetValueComputer.formattedMiMoTokenPlanExpiry(service)
            }
            guard let q = quotaFor(type: .time) ?? creditQuota() else { return "-" }
            if config.service == "codex" {
                return WidgetValueComputer.codexRateLimitDisplay(q).value
            }
            if q.type == .time {
                return WidgetValueComputer.formattedRemaining(quota: q)
            }
            guard let resetsAt = q.resetsAt else { return "-" }
            return WidgetValueComputer.countdownString(to: resetsAt) ?? "-"
        case .tokensRemaining:
            guard let q = quotaFor(type: .tokens) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .balance:
            guard let q = quotaFor(type: .money) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .sessionTokens:
            return WidgetValueComputer.formattedSessionTokens(svc.currentSession)
        case .usagePercent:
            guard let q = quotaFor(type: .tokens) ?? creditQuota() else { return "-" }
            return String(format: "%.0f%%", WidgetValueComputer.usageFraction(for: q) * 100)
        case .resetCountdown:
            if config.service == "mimo" {
                return WidgetValueComputer.formattedMiMoTokenPlanExpiry(service)
            }
            guard let q = quotaFor(type: .time) ?? creditQuota(),
                  let reset = q.resetsAt
            else { return "-" }
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: reset) else { return reset }
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MM/dd HH:mm"
            return displayFormatter.string(from: date)
        case .inputTokens:
            return WidgetValueComputer.formattedInputTokens(svc.currentSession)
        case .outputTokens:
            return WidgetValueComputer.formattedOutputTokens(svc.currentSession)
        case .dailyTokens:
            guard let q = quotaFor(type: .dailyTokens) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .monthlyTokens:
            guard let q = quotaFor(type: .monthlyTokens) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .costSpent:
            return WidgetValueComputer.formattedCostSpent(svc.currentSession)
        case .dailyRequests:
            guard let q = quotaFor(type: .dailyRequests) else { return "-" }
            return WidgetValueComputer.formattedRemaining(quota: q)
        case .monthlyRequests:
            guard let q = quotaFor(type: .monthlyRequests) else { return "-" }
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
            if config.service == "codex" {
                return WidgetValueComputer.codexSubscriptionStatus(svc)
            }
            if svc.error != nil { return "异常" }
            return svc.currentSession == nil && svc.quotas.isEmpty ? "未连接" : "已订阅"
        case .planName:
            return service?.label ?? config.service
        }
    }

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
                  let tokens = session.tokens,
                  let quota = svc.quotas.first(where: { $0.type == .tokens }),
                  let total = quota.total,
                  total > 0
            else { return 0 }
            return tokens / total
        case .resetCountdown:
            guard let q = quotaFor(type: .time) ?? creditQuota(),
                  let resetsAt = q.resetsAt,
                  let date = ISO8601DateFormatter().date(from: resetsAt)
            else { return 0 }
            let remaining = date.timeIntervalSinceNow
            let maxSeconds = q.type == .time ? max(q.total ?? 0, 1) : 2_592_000.0
            return max(0, min(1, remaining / maxSeconds))
        case .inputTokens:
            guard let value = svc.currentSession?.inputTokens,
                  let quota = svc.quotas.first(where: { $0.type == .tokens }),
                  let total = quota.total,
                  total > 0
            else { return 0 }
            return value / total
        case .outputTokens:
            guard let value = svc.currentSession?.outputTokens,
                  let quota = svc.quotas.first(where: { $0.type == .tokens }),
                  let total = quota.total,
                  total > 0
            else { return 0 }
            return value / total
        case .dailyTokens:
            return quotaFraction(type: .dailyTokens)
        case .monthlyTokens:
            return quotaFraction(type: .monthlyTokens)
        case .costSpent:
            guard let value = svc.currentSession?.costSpent,
                  let quota = svc.quotas.first(where: { $0.type == .money }),
                  let total = quota.total,
                  total > 0
            else { return 0 }
            return value / total
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
                  let total = quota.total,
                  total > 0
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

    private var metricTitle: String {
        if config.service == "codex", config.metric == .remainingTime {
            guard let quota = quotaFor(type: .time) else { return config.metric.displayName }
            return WidgetValueComputer.codexRateLimitDisplay(quota).detail ?? config.metric.displayName
        }
        if config.service == "mimo", config.metric == .resetCountdown {
            return "Token Plan 到期时间"
        }
        if config.service == "mimo", config.metric == .remainingTime {
            return "Token Plan 到期时间"
        }
        return config.metric.displayName
    }

    private var tooltipText: String {
        "\(service?.label ?? config.service) · \(metricTitle)"
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
