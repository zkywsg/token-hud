// token_hud/Overlay/OverlayFocusCard.swift
import SwiftUI

/// True when the focus card is rendered inside the notch-hosted expanded
/// surface (vs. the detached floating panel). The notch variant is a near-opaque
/// dark card so it flows seamlessly out of the black physical notch; the
/// detached variant is translucent glass that reads well over the desktop.
private struct HUDNotchHostedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var hudNotchHosted: Bool {
        get { self[HUDNotchHostedKey.self] }
        set { self[HUDNotchHostedKey.self] = newValue }
    }
}

/// Provider-accented rounded chip behind a metric icon — the small identity
/// anchor used by the focus card and the expanded notch header.
struct ServiceIconChip: View {
    let icon: String
    let accent: Color
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(accent.opacity(0.20))
            Image(systemName: icon)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: size, height: size)
    }
}

/// Page indicator for the focus carousel.
struct PageDots: View {
    let count: Int
    let currentIndex: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == currentIndex ? accent.opacity(0.9) : accent.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentIndex)
    }
}

/// Media-card style focus view for a single metric — the "Live Activity" look:
/// provider-accent progress ring + big hero value, metric label + icon, a reset
/// pill, a usage-trend waveform, and real control buttons. The outer glow and
/// waveform fill both follow the provider's accent color.
struct OverlayFocusCard: View {
    let config: WidgetConfig
    let state: StateFile?

    @Environment(\.panelAdaptiveScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hudNotchHosted) private var notchHosted
    /// Optional: the Settings preview renders without the app's stores.
    @Environment(UsageHistoryStore.self) private var usageHistory: UsageHistoryStore?
    @AppStorage("focusGaugeStyle") private var gaugeStyleRaw = FocusGaugeStyle.default.rawValue

    private var metric: WidgetMetricComputer { WidgetMetricComputer(config: config, state: state) }
    private var accent: Color { serviceAccentSwiftUIColor(for: config.service) }

    /// The magnitude the ring + waveform visualize. When the hero value reads as
    /// a percentage (e.g. "89% 7day"), track *that* so the gauge matches the big
    /// number; otherwise fall back to the usage fraction.
    private var gaugeFraction: Double {
        Self.percentage(in: metric.formattedValue) ?? metric.fraction
    }

    /// Parses a leading percentage from a formatted value ("89%", "89% 7day",
    /// "89.5%") into 0...1, or nil when the value isn't a percentage.
    static func percentage(in value: String) -> Double? {
        guard value.contains("%") else { return nil }
        var digits = ""
        for ch in value {
            if ch.isNumber || ch == "." {
                digits.append(ch)
            } else if ch == "%" || !digits.isEmpty {
                break
            }
        }
        guard let v = Double(digits) else { return nil }
        return (v / 100).clamped(to: 0...1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9 * scale) {
            topRow
            subtitle
            // Once enough days are recorded, per-day bars say far more than a
            // gauge or a running total; until then fall back to the gauge (when
            // there's a real denominator) or the plain counter rule.
            if let daily = dailyUsage {
                DailyUsageChart(days: daily, accent: accent)
                    .frame(height: 40 * scale)
            } else if metric.presentation.showsGauge {
                FocusGauge(
                    style: FocusGaugeStyle.from(gaugeStyleRaw),
                    fraction: gaugeFraction,
                    accent: accent
                )
                .frame(height: 40 * scale)
            } else {
                counterRule
                    .frame(height: 40 * scale)
            }
            controlsRow
        }
        .padding(.horizontal, 16 * scale)
        .padding(.top, 13 * scale)
        .padding(.bottom, 11 * scale)
        // Fill the surface so the card *is* the panel — otherwise the backdrop
        // shows through below the content as a black strip.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusCardBackground(accent: accent, notchHosted: notchHosted))
    }

    // MARK: - Top: ring + hero value / label + pill

    private var topRow: some View {
        HStack(alignment: .top, spacing: 12 * scale) {
            HStack(spacing: 10 * scale) {
                // The ring is a proportion too — only shown when one exists.
                if metric.presentation.showsGauge {
                    ProgressRing(fraction: gaugeFraction, accent: accent, size: 24 * scale)
                }
                Text(metric.formattedValue)
                    .font(.system(size: 34 * scale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: metric.formattedValue)
            }

            Spacer(minLength: 8 * scale)

            VStack(alignment: .trailing, spacing: 6 * scale) {
                HStack(spacing: 6 * scale) {
                    Text(topLabel)
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    ServiceIconChip(icon: metric.icon, accent: accent, size: 20 * scale)
                }
                if let pill = pillText {
                    Text(pill)
                        .font(.system(size: 10.5 * scale, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .padding(.horizontal, 8 * scale)
                        .padding(.vertical, 4 * scale)
                        .background(
                            accent.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                                .stroke(accent.opacity(0.30), lineWidth: 0.5)
                        )
                }
            }
        }
    }

    /// Per-day history for this provider, or nil when too little is recorded to
    /// chart (the first days after install can't be back-filled).
    private var dailyUsage: [DailyUsage]? {
        guard let usageHistory,
              usageHistory.hasChartableHistory(for: config.service)
        else { return nil }
        return usageHistory.dailyUsage(for: config.service, days: 7)
    }

    /// Stand-in for the gauge on unbounded counters: a soft accent rule that
    /// fades out, reading as "a running total" rather than "x% of a limit".
    private var counterRule: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Spacer(minLength: 0)
            Text("累计用量 · 无额度上限")
                .font(.system(size: 9.5 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.7), accent.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2.5 * scale)
            Spacer(minLength: 0)
        }
    }

    private var topLabel: String {
        metric.metricTitle.isEmpty ? metric.serviceLabel : metric.metricTitle
    }

    /// Secondary detail (e.g. Codex rate-limit reset) shown as a pill; hidden
    /// when the metric has no secondary line.
    private var pillText: String? {
        guard let detail = metric.formattedDetail, !detail.isEmpty else { return nil }
        return detail
    }

    // MARK: - Subtitle

    private var subtitle: some View {
        Text(subtitleText)
            .font(.system(size: 12 * scale, weight: .medium))
            .italic()
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var subtitleText: String {
        // A raw total means little without a reference. Where the cycle position
        // is known, project it; while history is still building, say so rather
        // than implying the chart is missing by accident.
        if let pace = paceText { return pace }
        let title = metric.metricTitle
        if title.isEmpty || title == metric.serviceLabel {
            return metric.serviceLabel
        }
        return "\(metric.serviceLabel) · \(title)"
    }

    /// The projection is derived from the cycle position alone, so it works from
    /// the first launch — it must not be gated on recorded history (an earlier
    /// version returned early when history was empty, which hid both).
    private var paceText: String? {
        guard let projected = projectedCycleTotal else { return nil }
        return "按此节奏 · 周期约 \(WidgetValueComputer.formatTokensPublic(projected))"
    }

    /// Projection needs a cycle to be a fraction *of*; providers without a time
    /// quota (Claude's rolling local log) get no forecast.
    private var projectedCycleTotal: Double? {
        guard let service = state?.services[config.service],
              let timeQuota = service.quotas.first(where: { $0.type == .time }),
              let total = timeQuota.total, total > 0
        else { return nil }
        let elapsed = timeQuota.used / total
        let used = service.quotas.first { $0.type == .tokens || $0.type == .monthlyTokens }?.used ?? 0
        return UsageHistoryCalculator.projectedCycleTotal(used: used, cycleElapsedFraction: elapsed)
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: 10 * scale) {
            controlButton(icon: "chevron.down", size: 34 * scale) {
                NotificationCenter.default.post(name: .hudCollapse, object: nil)
            }
            Spacer(minLength: 0)
            controlButton(icon: "arrow.clockwise", size: 34 * scale) {
                NotificationCenter.default.post(name: .hudRefreshNow, object: nil)
            }
            controlButton(icon: "ellipsis", size: 34 * scale) {
                NotificationCenter.default.post(name: .hudOpenSettings, object: nil)
            }
        }
    }

    private func controlButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress ring

private struct ProgressRing: View {
    let fraction: Double
    let accent: Color
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: size * 0.16)
            Circle()
                .trim(from: 0, to: fraction.clamped(to: 0...1))
                .stroke(accent, style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Card background (glass + accent glow)

private struct FocusCardBackground: View {
    let accent: Color
    /// Notch-hosted → near-opaque dark card flowing from the physical notch;
    /// detached → translucent glass over the desktop.
    var notchHosted: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Square top in the notch so the card meets the black cap flush; fully
    /// rounded when floating detached.
    private var shape: AnyShape {
        if notchHosted {
            // Matches the hosted body panel's bottom radius exactly; a larger
            // radius here would let the panel's squarer corner peek out behind
            // the card.
            return AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0,
                style: .continuous
            ))
        }
        return AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    var body: some View {
        let shape = self.shape
        return ZStack {
            baseFill(shape)
            // The flowing light. In the notch it's confined to the outer edge —
            // and kept away from the top — so the interior and the top seam stay
            // as black as the physical notch; detached, it fills the glass.
            flowingLightField
                .mask(flowMask(shape))
                .allowsHitTesting(false)
            strokeOverlay(shape)
        }
        .compositingGroup()
        // In the notch, any glow around the top edge would redraw the very seam
        // we're trying to erase, so the accent shadow is dropped there and only
        // a soft downward shadow remains.
        .shadow(color: accent.opacity(reduceTransparency || notchHosted ? 0 : 0.40),
                radius: 22, y: 6)
        .shadow(color: Color.black.opacity(notchHosted ? 0.25 : 0.35),
                radius: 12, y: notchHosted ? 10 : 6)
    }

    /// Detached: hairline all the way around. Notch: the top edge is left
    /// unstroked (faded out) so no line appears where the cap meets the card.
    @ViewBuilder
    private func strokeOverlay(_ shape: AnyShape) -> some View {
        if notchHosted {
            shape.stroke(accent.opacity(0.16), lineWidth: 0.8)
                .mask(topFade)
        } else {
            shape.stroke(accent.opacity(0.22), lineWidth: 0.8)
        }
    }

    /// Detached: the whole card. Notch: a rim along the sides and bottom.
    ///
    /// The rim is built from soft linear falloffs and only then clipped by the
    /// card shape, so the outer boundary follows the rounded corners exactly.
    /// (Masking with a thick `stroke` instead would inset the corner radius past
    /// zero — 18 − 54/2 < 0 — and render square inner corners.)
    @ViewBuilder
    private func flowMask(_ shape: AnyShape) -> some View {
        if notchHosted {
            ZStack {
                LinearGradient(
                    stops: [.init(color: .white, location: 0.0), .init(color: .clear, location: 0.30)],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.70), .init(color: .white, location: 1.0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .blendMode(.plusLighter)
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.45), .init(color: .white, location: 1.0)],
                    startPoint: .top, endPoint: .bottom
                )
                .blendMode(.plusLighter)
            }
            .compositingGroup()
            .mask(topFade)
            .mask(shape)
        } else {
            shape
        }
    }

    /// Transparent at the top, opaque lower down — used to keep every decorative
    /// edge treatment away from the notch seam.
    private var topFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.18),
                .init(color: .white, location: 0.55)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func baseFill(_ shape: AnyShape) -> some View {
        if notchHosted {
            // Flat pure black — the exact same fill the cap uses. A gradient here
            // would land a slightly different value against the cap and read as a
            // seam, so the notch variant deliberately has no vertical shading.
            shape.fill(Color.black)
        } else if reduceTransparency {
            shape.fill(Theme.SurfaceLevel.raised.gradient)
        } else {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.55))
        }
    }

    /// A few large, heavily-blurred light blobs that slowly drift over the card
    /// on independent sine paths and add together (`plusLighter`), reading as
    /// ambient light rippling across the surface rather than a hard highlight.
    private var flowingLightField: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let d = max(w, h)

            if reduceMotion {
                staticField(w: w, h: h, d: d)
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        blob(accent.opacity(0.85), diameter: d * 0.85)
                            .position(x: w * (0.30 + 0.34 * cos(t * 0.52)),
                                      y: h * (0.35 + 0.60 * sin(t * 0.67)))
                        blob(Color.white.opacity(0.26), diameter: d * 0.62)
                            .position(x: w * (0.62 + 0.36 * sin(t * 0.43 + 1)),
                                      y: h * (0.55 + 0.65 * cos(t * 0.58 + 2)))
                        blob(accent.opacity(0.68), diameter: d * 1.0)
                            .position(x: w * (0.78 + 0.30 * cos(t * 0.37 + 3)),
                                      y: h * (0.42 + 0.58 * sin(t * 0.49 + 1)))
                    }
                    .blur(radius: 24)
                    .blendMode(.plusLighter)
                }
            }
        }
    }

    private func staticField(w: CGFloat, h: CGFloat, d: CGFloat) -> some View {
        ZStack {
            blob(accent.opacity(0.45), diameter: d * 0.95).position(x: w * 0.32, y: h * 0.30)
            blob(accent.opacity(0.30), diameter: d * 1.10).position(x: w * 0.80, y: h * 0.55)
        }
        .blur(radius: 28)
        .blendMode(.plusLighter)
    }

    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Paged focus carousel

/// One focus card per page with swipe paging + dots — the "single-metric focus,
/// swipe between providers" layout.
struct OverlayFocusView: View {
    let widgets: [WidgetConfig]
    let state: StateFile?

    @Environment(\.panelAdaptiveScale) private var scale
    /// Optional: absent in the Settings preview, present in the notch/detached
    /// panels. Publishing the page here lets the notch header track the swipe.
    @Environment(NotchHostState.self) private var hostState: NotchHostState?
    @State private var currentID: UUID?

    private var currentIndex: Int {
        guard let currentID, let idx = widgets.firstIndex(where: { $0.id == currentID }) else { return 0 }
        return idx
    }

    var body: some View {
        if widgets.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(widgets) { config in
                            OverlayFocusCard(config: config, state: state)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(config.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentID)
            }
            // Dots ride inside the card instead of taking their own row below,
            // which would expose the backdrop as a strip under the card.
            .overlay(alignment: .bottom) {
                if widgets.count > 1 {
                    PageDots(count: widgets.count, currentIndex: currentIndex, accent: .white)
                        .padding(.bottom, 5 * scale)
                }
            }
            .onAppear {
                if currentID == nil { currentID = widgets.first?.id }
                hostState?.focusedWidgetID = currentID
            }
            .onChange(of: currentID) { _, newValue in
                hostState?.focusedWidgetID = newValue
            }
        }
    }
}
