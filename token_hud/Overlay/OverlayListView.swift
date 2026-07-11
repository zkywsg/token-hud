// token_hud/Overlay/OverlayListView.swift
import SwiftUI

/// HUD overlay layout modes, chosen in Settings and shared across the hosted
/// expanded panel and the detached floating panel.
enum OverlayLayout: String, CaseIterable {
    case summary   // B: promoted hero (first item) + scrolling list
    case drawer    // A: plain vertical list, panel grows to fit then scrolls
    case paged     // C: one item per page (placeholder — falls back to list)

    static func from(_ raw: String) -> OverlayLayout {
        OverlayLayout(rawValue: raw) ?? .summary
    }
}

fileprivate enum OverlayPresentation {
    case standard
    case summary
}

/// Dispatches the configured layout. `summary` is implemented; `drawer` and
/// `paged` currently render the plain list (A/C are a later round).
struct OverlayContentView: View {
    let layout: OverlayLayout
    let widgets: [WidgetConfig]
    let state: StateFile?
    var entranceState: Bool? = nil

    var body: some View {
        switch layout {
        case .summary:
            OverlaySummaryView(
                widgets: widgets,
                state: state,
                entranceState: entranceState
            )
        case .drawer:
            OverlayListView(widgets: widgets, state: state)
        case .paged:
            OverlayPagedView(widgets: widgets, state: state)
        }
    }
}

// MARK: - C: paged (one item per page)

struct OverlayPagedView: View {
    let widgets: [WidgetConfig]
    let state: StateFile?

    @Environment(\.panelAdaptiveScale) private var scale
    @State private var currentID: UUID?

    private var currentIndex: Int {
        guard let currentID, let idx = widgets.firstIndex(where: { $0.id == currentID }) else { return 0 }
        return idx
    }

    var body: some View {
        VStack(spacing: 6 * scale) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(widgets) { config in
                            OverlayHeroRow(config: config, state: state)
                                .frame(width: geo.size.width, alignment: .leading)
                                .frame(maxHeight: .infinity, alignment: .center)
                                .id(config.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentID)
            }
            if widgets.count > 1 {
                PageDots(count: widgets.count, currentIndex: currentIndex, accent: .white)
            }
        }
        .onAppear { if currentID == nil { currentID = widgets.first?.id } }
    }
}

private struct PageDots: View {
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

// MARK: - B: summary (hero + list)

struct OverlaySummaryView: View {
    let widgets: [WidgetConfig]
    let state: StateFile?
    let entranceState: Bool?

    @Environment(\.panelAdaptiveScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entranceVisible = true
    @State private var entranceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hero = widgets.first {
                OverlayHeroRow(config: hero, state: state, presentation: .summary)
                    .padding(.bottom, 4 * scale)
                    .summaryEntrance(
                        visible: entranceVisible,
                        rowIndex: 0,
                        scale: scale,
                        reduceMotion: reduceMotion
                    )
            }
            if widgets.count > 1 {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(widgets.dropFirst().enumerated()), id: \.element.id) { index, config in
                            VStack(alignment: .leading, spacing: 0) {
                                Divider().overlay(Color.white.opacity(index == 0 ? 0.10 : 0.06))
                                OverlayListRow(config: config, state: state, presentation: .summary)
                            }
                            .summaryEntrance(
                                visible: entranceVisible,
                                rowIndex: index + 1,
                                scale: scale,
                                reduceMotion: reduceMotion
                            )
                        }
                    }
                }
            }
        }
        .onChange(of: entranceState, initial: true) { oldValue, newValue in
            updateEntrance(previous: oldValue, current: newValue)
        }
        .onDisappear {
            entranceTask?.cancel()
            entranceTask = nil
        }
    }

    private func updateEntrance(previous: Bool?, current: Bool?) {
        entranceTask?.cancel()
        entranceTask = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true

        guard SummaryEntranceAnimation.shouldAnimate(previous: previous, current: current) else {
            withTransaction(transaction) {
                entranceVisible = true
            }
            return
        }

        withTransaction(transaction) {
            entranceVisible = false
        }

        entranceTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, entranceState == true else { return }
            entranceVisible = true
            entranceTask = nil
        }
    }
}

private extension View {
    func summaryEntrance(
        visible: Bool,
        rowIndex: Int,
        scale: CGFloat,
        reduceMotion: Bool
    ) -> some View {
        let animation = reduceMotion
            ? Animation.easeOut(duration: 0.12)
            : Animation.easeOut(duration: SummaryEntranceAnimation.itemDuration).delay(
                SummaryEntranceAnimation.delay(rowIndex: rowIndex, reduceMotion: reduceMotion)
            )

        return opacity(visible ? 1 : 0)
            .offset(y: reduceMotion || visible ? 0 : 5 * scale)
            .animation(animation, value: visible)
    }
}

// MARK: - A / fallback: plain list

struct OverlayListView: View {
    let widgets: [WidgetConfig]
    let state: StateFile?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(widgets.enumerated()), id: \.element.id) { index, config in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                    OverlayListRow(config: config, state: state)
                }
            }
        }
    }
}

// MARK: - Hero row (promoted first item)

struct OverlayHeroRow: View {
    let config: WidgetConfig
    let state: StateFile?
    fileprivate var presentation: OverlayPresentation = .standard

    @Environment(\.panelAdaptiveScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metric: WidgetMetricComputer { WidgetMetricComputer(config: config, state: state) }
    private var accent: Color { serviceAccentSwiftUIColor(for: config.service) }

    var body: some View {
        switch presentation {
        case .standard:
            standardBody
        case .summary:
            summaryBody
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(spacing: 8 * scale) {
                iconChip
                VStack(alignment: .leading, spacing: 0) {
                    Text(metric.serviceLabel)
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    if !metric.metricTitle.isEmpty {
                        Text(metric.metricTitle)
                            .font(.system(size: 10 * scale, weight: .regular))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8 * scale)
            }

            animatedValue(size: 30 * scale)

            if showsBar {
                UsageBar(fraction: metric.fraction, accent: accent, height: 5 * scale)
            }
        }
    }

    private var summaryBody: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(alignment: .center, spacing: 8 * scale) {
                iconChip
                VStack(alignment: .leading, spacing: 0) {
                    Text(metric.serviceLabel)
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    if !metric.metricTitle.isEmpty {
                        Text(metric.metricTitle)
                            .font(.system(size: 9 * scale, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                            .textCase(.uppercase)
                    }
                }
                Spacer(minLength: 8 * scale)
                VStack(alignment: .trailing, spacing: 0) {
                    animatedValue(size: 26 * scale)
                    if let detail = metric.formattedDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 9 * scale, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .textCase(.uppercase)
                    }
                }
                .frame(minWidth: 76 * scale, alignment: .trailing)
            }

            if showsBar {
                UsageBar(
                    fraction: metric.fraction,
                    accent: accent,
                    height: 5 * scale,
                    presentation: .summary
                )
            }
        }
    }

    private func animatedValue(size: CGFloat) -> some View {
        Text(metric.formattedValue)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: metric.formattedValue)
    }

    private var iconChip: some View {
        ServiceIconChip(icon: metric.icon, accent: accent, size: 24 * scale)
    }

    private var showsBar: Bool {
        switch config.metric {
        case .subscriptionStatus, .planName, .resetCountdown: return false
        default: return metric.fraction > 0
        }
    }
}

// MARK: - Standard list row

struct OverlayListRow: View {
    let config: WidgetConfig
    let state: StateFile?
    fileprivate var presentation: OverlayPresentation = .standard

    @Environment(\.panelAdaptiveScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metric: WidgetMetricComputer { WidgetMetricComputer(config: config, state: state) }
    private var accent: Color { serviceAccentSwiftUIColor(for: config.service) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(alignment: .center, spacing: 8 * scale) {
                ServiceIconChip(icon: metric.icon, accent: accent, size: 20 * scale)

                VStack(alignment: .leading, spacing: 0) {
                    Text(metric.serviceLabel)
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !metric.metricTitle.isEmpty {
                        Text(metric.metricTitle)
                            .font(.system(size: 9 * scale, weight: .regular))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8 * scale)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(metric.formattedValue)
                        .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(
                            reduceMotion ? nil : .snappy(duration: 0.35),
                            value: metric.formattedValue
                        )
                    if presentation == .summary {
                        if let detail = metric.formattedDetail, !detail.isEmpty {
                            detailText(detail)
                                .minimumScaleFactor(0.65)
                        }
                    } else if let detail = metric.formattedDetail {
                        detailText(detail)
                    }
                }
                .modifier(ValueColumnFrame(presentation: presentation, scale: scale))
            }

            if showsBar {
                UsageBar(
                    fraction: metric.fraction,
                    accent: accent,
                    height: 4 * scale,
                    presentation: presentation
                )
            }
        }
        .padding(.vertical, 6 * scale)
    }

    private func detailText(_ detail: String) -> some View {
        Text(detail)
            .font(.system(size: 9 * scale, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.white.opacity(0.5))
            .lineLimit(1)
    }

    private var showsBar: Bool {
        switch config.metric {
        case .subscriptionStatus, .planName, .resetCountdown: return false
        default: return metric.fraction > 0
        }
    }
}

private struct ValueColumnFrame: ViewModifier {
    let presentation: OverlayPresentation
    let scale: CGFloat

    func body(content: Content) -> some View {
        if presentation == .summary {
            content.frame(width: 76 * scale, alignment: .trailing)
        } else {
            content.frame(minWidth: 64 * scale, alignment: .trailing)
        }
    }
}

// MARK: - Shared icon chip

/// Provider-accented rounded chip behind a metric icon — gives each row a small
/// identity anchor instead of a bare glyph.
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

// MARK: - Shared usage bar

/// Shows remaining capacity (1 - usage) filled, colored by usage severity.
/// Track is tinted with the provider accent so the row still reads as that
/// service even when nearly empty.
struct UsageBar: View {
    let fraction: Double
    let accent: Color
    var height: CGFloat = 4
    fileprivate var presentation: OverlayPresentation = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let remaining = (1 - fraction).clamped(to: 0...1)
            ZStack(alignment: .leading) {
                Capsule().fill(accent.opacity(0.22))
                Capsule()
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(remaining))
                    .shadow(
                        color: showsGlow ? barColor.opacity(0.32) : .clear,
                        radius: showsGlow ? 3 : 0
                    )
                    .animation(
                        animatesWidth ? .easeOut(duration: 0.22) : nil,
                        value: remaining
                    )
            }
        }
        .frame(height: height)
    }

    private var animatesWidth: Bool {
        presentation == .summary && !reduceMotion
    }

    private var showsGlow: Bool {
        presentation == .summary && fraction >= 0.85
    }

    private var barColor: Color {
        switch fraction {
        case 0..<0.5:   return Color(red: 0.30, green: 0.86, blue: 0.55)
        case 0.5..<0.8: return Color(red: 1.0, green: 0.76, blue: 0.20)
        default:        return Color(red: 1.0, green: 0.28, blue: 0.34)
        }
    }
}
