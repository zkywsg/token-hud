import SwiftUI

/// Unified hosted notch surface. Collapsed and expanded states share the
/// same view; visual transition is driven entirely by
/// `hostState.expansionProgress` so the window itself never resizes and
/// SwiftUI transitions don't cross-fade two different view hierarchies.
struct NotchHostedSurfaceView: View {
    @Environment(NotchHostState.self) private var hostState
    @Environment(WidgetStore.self) private var store
    @Environment(StateWatcher.self) private var watcher
    @AppStorage("overlayMode") private var overlayMode = "compact"

    var body: some View {
        GeometryReader { geo in
            let layout = surfaceLayout(in: geo.size)
            let status = collapsedStatus
            let adaptiveScale = adaptiveScale(for: layout.body.size)

            ZStack(alignment: .topLeading) {
                bodyPanel(layout.body, opacity: layout.contentOpacity, adaptiveScale: adaptiveScale, layout: layout)
                topCap(layout.topCap, bodyHeight: layout.body.height, layout: layout)
                statusSlot(layout.leftStatusSlot, isLeading: true, status: status, layout: layout)
                statusSlot(layout.rightStatusSlot, isLeading: false, status: status, layout: layout)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .environment(\.panelAdaptiveScale, adaptiveScale)
        }
    }

    // MARK: - Pieces

    private func topCap(_ rect: CGRect, bodyHeight: CGFloat, layout: NotchHostedSurfaceLayout) -> some View {
        let topY = topOffset(for: rect, in: layout)
        let collapsedRadius = min(14, max(0, rect.height / 2))
        let bottomRadius = bodyHeight > 0.5 ? 0 : collapsedRadius

        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0
        )
        .fill(Color.black.opacity(0.97))
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: topY)
    }

    @ViewBuilder
    private func statusSlot(
        _ rect: CGRect,
        isLeading: Bool,
        status: NotchCollapsedStatusValue,
        layout: NotchHostedSurfaceLayout
    ) -> some View {
        if rect.width > 1 {
            let topY = topOffset(for: rect, in: layout)

            if isLeading {
                progressBar(fraction: status.fraction)
                    .frame(
                        width: max(24, min(42, rect.width - 14)),
                        height: 5
                    )
                    .frame(width: rect.width, height: rect.height, alignment: .center)
                    .offset(x: rect.minX, y: topY)
                    .opacity(1 - layout.contentOpacity)
            } else {
                Text(status.percentText)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: rect.width, height: rect.height, alignment: .center)
                    .offset(x: rect.minX, y: topY)
                    .opacity(1 - layout.contentOpacity)
            }
        }
    }

    private func bodyPanel(
        _ rect: CGRect,
        opacity: CGFloat,
        adaptiveScale: CGFloat,
        layout: NotchHostedSurfaceLayout
    ) -> some View {
        let topY = topOffset(for: rect, in: layout)
        let bottomRadius = min(16, max(0, rect.height / 2))
        let isVisible = rect.height > 0.5

        return ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: bottomRadius,
                bottomTrailingRadius: bottomRadius,
                topTrailingRadius: 0
            )
            .fill(Color.black.opacity(0.96))
            .shadow(color: Color.black.opacity(0.24 * opacity), radius: 18, y: 10)

            VStack {
                if overlayMode == "grouped" {
                    GroupedOverlayView(
                        widgets: store.widgets,
                        state: watcher.effectiveState
                    )
                } else {
                    CompactOverlayContent()
                }
            }
            .padding(.horizontal, 12 * adaptiveScale)
            .padding(.vertical, 8 * adaptiveScale)
            .opacity(opacity)
            .scaleEffect(0.98 + 0.02 * opacity)
        }
        .frame(width: rect.width, height: rect.height)
        .clipped()
        .offset(x: rect.minX, y: topY)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(hostState.isExpanded && isVisible)
    }

    private func progressBar(fraction: Double) -> some View {
        GeometryReader { geo in
            let value = fraction.clamped(to: 0...1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(progressColor(for: value))
                    .frame(width: geo.size.width * value)
            }
        }
    }

    private func progressColor(for fraction: Double) -> Color {
        if fraction >= 0.85 { return Color(red: 1.0, green: 0.27, blue: 0.32) }
        if fraction >= 0.65 { return Color(red: 1.0, green: 0.84, blue: 0.10) }
        return Color(red: 0.25, green: 0.86, blue: 0.48)
    }

    // MARK: - Layout helpers

    private func topOffset(for rect: CGRect, in layout: NotchHostedSurfaceLayout) -> CGFloat {
        layout.surfaceSize.height - rect.maxY
    }

    private func surfaceLayout(in size: CGSize) -> NotchHostedSurfaceLayout {
        if let geometry = hostState.geometry, geometry.hasNotch {
            let screenFrame = hostState.screenFrame == .zero
                ? CGRect(origin: .zero, size: size)
                : hostState.screenFrame
            return NotchGeometryCalculator.hostedSurfaceLayout(
                screenFrame: screenFrame,
                geometry: geometry,
                expansionProgress: hostState.expansionProgress
            )
        }
        let fallbackScreen = CGRect(origin: .zero, size: size)
        let fallbackGeometry = NotchGeometryCalculator.noNotchFallback(screenFrame: fallbackScreen)
        return NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: fallbackScreen,
            geometry: fallbackGeometry,
            expansionProgress: hostState.expansionProgress
        )
    }

    private func adaptiveScale(for size: CGSize) -> CGFloat {
        let baseHeight: CGFloat = 60
        let idealHeight: CGFloat
        if overlayMode == "grouped" {
            let serviceCount = Set(store.widgets.map(\.service)).count
            idealHeight = max(baseHeight, CGFloat(serviceCount) * 32 + 16)
        } else {
            idealHeight = baseHeight
        }
        guard size.height > 1 else { return 1 }
        return (size.height / idealHeight).clamped(to: 0.5...3.0)
    }

    // MARK: - Status

    private var collapsedStatus: NotchCollapsedStatusValue {
        NotchCollapsedStatusComputer.value(
            widgets: store.widgets,
            state: watcher.effectiveState
        )
    }
}

// MARK: - Shared collapsed status calculation

struct NotchCollapsedStatusValue: Equatable {
    let fraction: Double

    var percentText: String {
        "\(Int((fraction.clamped(to: 0...1) * 100).rounded()))%"
    }
}

enum NotchCollapsedStatusComputer {
    static func value(widgets: [WidgetConfig], state: StateFile) -> NotchCollapsedStatusValue {
        for config in widgets {
            if let fraction = fraction(for: config, state: state) {
                return NotchCollapsedStatusValue(fraction: fraction)
            }
        }
        for service in state.services.values {
            if let quota = service.quotas.first(where: { ($0.total ?? 0) > 0 }) {
                return NotchCollapsedStatusValue(fraction: WidgetValueComputer.usageFraction(for: quota))
            }
        }
        return NotchCollapsedStatusValue(fraction: 0)
    }

    private static func fraction(for config: WidgetConfig, state: StateFile) -> Double? {
        guard let service = state.services[config.service] else { return nil }

        switch config.metric {
        case .remainingTime:
            return quotaFraction(type: .time, service: service, config: config)
        case .tokensRemaining, .usagePercent:
            return quotaFraction(type: .tokens, service: service, config: config)
                ?? creditFraction(service: service)
        case .balance:
            return quotaFraction(type: .money, service: service, config: config)
        case .dailyTokens:
            return quotaFraction(type: .dailyTokens, service: service, config: config)
        case .monthlyTokens:
            return quotaFraction(type: .monthlyTokens, service: service, config: config)
        case .dailyRequests:
            return quotaFraction(type: .dailyRequests, service: service, config: config)
        case .monthlyRequests:
            return quotaFraction(type: .monthlyRequests, service: service, config: config)
        case .rateLimitStatus:
            return service.quotas
                .compactMap { quota -> Double? in
                    guard (quota.total ?? 0) > 0 else { return nil }
                    return WidgetValueComputer.usageFraction(for: quota)
                }
                .max()
        case .creditsRemaining, .creditsUsed, .sessionCredits:
            return creditFraction(service: service)
        case .subscriptionStatus:
            return service.error == nil ? 1 : 0
        case .sessionTokens, .inputTokens, .outputTokens, .costSpent,
             .resetCountdown, .sessionDuration, .tokensPerMinute,
             .inputOutputRatio, .costPerRequest, .planName:
            return firstQuotaFraction(service: service)
        }
    }

    private static func quotaFraction(type: QuotaType, service: Service, config: WidgetConfig) -> Double? {
        let matching = service.quotas.filter { $0.type == type }
        guard !matching.isEmpty else { return nil }
        let quota = config.quotaIndex < matching.count ? matching[config.quotaIndex] : matching[0]
        guard (quota.total ?? 0) > 0 else { return nil }
        return WidgetValueComputer.usageFraction(for: quota)
    }

    private static func creditFraction(service: Service) -> Double? {
        guard let quota = service.quotas.first(where: { $0.unit.lowercased() == "credits" }),
              (quota.total ?? 0) > 0
        else { return nil }
        return WidgetValueComputer.usageFraction(for: quota)
    }

    private static func firstQuotaFraction(service: Service) -> Double? {
        guard let quota = service.quotas.first(where: { ($0.total ?? 0) > 0 }) else { return nil }
        return WidgetValueComputer.usageFraction(for: quota)
    }
}
