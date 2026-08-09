import SwiftUI

/// Unified hosted notch surface. Collapsed and expanded states share the
/// same view; visual transition is driven entirely by
/// `hostState.expansionProgress` so the window itself never resizes and
/// SwiftUI transitions don't cross-fade two different view hierarchies.
struct NotchHostedSurfaceView: View {
    @Environment(NotchHostState.self) private var hostState
    @Environment(WidgetStore.self) private var store
    @Environment(StateWatcher.self) private var watcher
    @AppStorage("widgetSizeScale") private var widgetSizeScale = 1.0
    @AppStorage("notchCollapsedLeadingSource") private var collapsedLeadingSource = NotchCollapsedSourceStore.autoRawValue
    @AppStorage("notchCollapsedTrailingSource") private var collapsedTrailingSource = NotchCollapsedSourceStore.autoRawValue

    var body: some View {
        GeometryReader { geo in
            let layout = surfaceLayout(in: geo.size)
            let status = collapsedStatus
            let adaptiveScale = adaptiveScale(for: layout.body.size)

            ZStack(alignment: .topLeading) {
                bodyPanel(layout.body, opacity: layout.contentOpacity, adaptiveScale: adaptiveScale, layout: layout)
                topCap(layout.topCap, bodyHeight: layout.body.height, layout: layout)
                if layout.body.height > 0.5 {
                    // Expanded: the collapsed pill's 56pt ears end up stranded at
                    // the outer edges of the much wider cap, so the expanded state
                    // gets its own header laid out against the real cap width.
                    expandedHeader(layout: layout)
                } else {
                    statusSlot(layout.leftStatusSlot, isLeading: true, status: status, layout: layout)
                    statusSlot(layout.rightStatusSlot, isLeading: false, status: status, layout: layout)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .environment(\.panelAdaptiveScale, adaptiveScale)
        }
    }

    // MARK: - Pieces

    private func topCap(_ rect: CGRect, bodyHeight: CGFloat, layout: NotchHostedSurfaceLayout) -> some View {
        let topY = topOffset(for: rect, in: layout)
        let collapsedRadius = min(14, max(0, rect.height / 2))
        let isExpanded = bodyHeight > 0.5
        let bottomRadius = isExpanded ? 0 : collapsedRadius
        let capShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0
        )

        return ZStack {
            if isExpanded {
                // Expanded: flat pure black — byte-identical to the focus card's
                // fill below, and no stroke, so the physical notch, the cap and
                // the card read as one continuous black surface with no seam.
                capShape.fill(Color.black)
            } else {
                // Collapsed: solid black so it reads as the physical notch pill.
                capShape.fill(.thinMaterial)
                capShape.fill(Color.black.opacity(0.90))
                capShape.stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: topY)
    }

    /// Menu-bar row shown while expanded: provider identity on the left of the
    /// notch, the headline value on the right. Both sides are inset from the cap
    /// edges and stop short of the notch gap, so nothing sits under the camera.
    @ViewBuilder
    private func expandedHeader(layout: NotchHostedSurfaceLayout) -> some View {
        let cap = layout.topCap
        let gap = layout.notchGap
        let topY = topOffset(for: cap, in: layout)
        let sideInset: CGFloat = 14
        let gapPad: CGFloat = 10
        let leftWidth = max(0, (gap.minX - gapPad) - (cap.minX + sideInset))
        let rightWidth = max(0, (cap.maxX - sideInset) - (gap.maxX + gapPad))

        if let metric = headlineMetric {
            let accent = serviceAccentSwiftUIColor(for: metric.config.service)

            if leftWidth > 40 {
                HStack(spacing: 6) {
                    ServiceIconChip(icon: metric.computer.icon, accent: accent, size: 15)
                    Text(metric.computer.serviceLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .frame(width: leftWidth, height: cap.height, alignment: .leading)
                .offset(x: cap.minX + sideInset, y: topY)
            }

            if rightWidth > 40 {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text(metric.computer.formattedValue)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: rightWidth, height: cap.height, alignment: .trailing)
                .offset(x: gap.maxX + gapPad, y: topY)
            }
        }
    }

    /// The metric the expanded header describes — whichever card the carousel is
    /// currently showing, so swiping updates the menu-bar row with it.
    private var headlineMetric: (config: WidgetConfig, computer: WidgetMetricComputer)? {
        let focused = hostState.focusedWidgetID.flatMap { id in
            store.widgets.first { $0.id == id }
        }
        guard let config = focused ?? store.widgets.first else { return nil }
        return (config, WidgetMetricComputer(config: config, state: watcher.effectiveState))
    }

    @ViewBuilder
    private func statusSlot(
        _ rect: CGRect,
        isLeading: Bool,
        status: NotchCollapsedStatusDisplay,
        layout: NotchHostedSurfaceLayout
    ) -> some View {
        if rect.width > 1 {
            let topY = topOffset(for: rect, in: layout)

            // Kept visible while expanded too: the menu-bar strip beside the
            // notch would otherwise read as an empty black band.
            if isLeading {
                progressBar(fraction: status.leadingFraction)
                    .frame(
                        width: max(24, min(42, rect.width - 14)),
                        height: 5
                    )
                    .frame(width: rect.width, height: rect.height, alignment: .center)
                    .offset(x: rect.minX, y: topY)
            } else {
                Text(status.trailingText)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: rect.width, height: rect.height, alignment: .center)
                    .offset(x: rect.minX, y: topY)
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
        let panelShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0
        )

        return ZStack {
            // A flat black backdrop fills the whole body so no desktop shows
            // through above/below the card — the cap, backdrop and card are all
            // the same black, which is what makes the notch fusion seamless.
            panelShape.fill(Color.black)

            OverlayFocusView(widgets: store.widgets, state: watcher.effectiveState)
                .environment(\.panelAdaptiveScale, widgetSizeScale)
                .environment(\.hudNotchHosted, true)
                .opacity(opacity)
                .scaleEffect(0.98 + 0.02 * opacity)
        }
        .frame(width: rect.width, height: rect.height)
        .clipped()
        .offset(x: rect.minX, y: topY)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(hostState.isExpanded && isVisible)
    }

    @ViewBuilder
    private func progressBar(fraction: Double) -> some View {
        if fraction <= 0 {
            // No denominator (or nothing consumed yet): an empty bar would read
            // as "plenty left", so show a neutral rule instead.
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(height: 2)
        } else {
            filledProgressBar(fraction: fraction)
        }
    }

    private func filledProgressBar(fraction: Double) -> some View {
        GeometryReader { geo in
            let value = fraction.clamped(to: 0...1)
            let color = progressColor(for: value)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * value)
                    // Subtle glow when usage is critical, so a nearly-exhausted
                    // quota reads at a glance even in the tiny collapsed strip.
                    .shadow(color: value >= 0.85 ? color.opacity(0.85) : .clear, radius: 3)
                    .animation(.easeOut(duration: 0.3), value: value)
            }
        }
    }

    private func progressColor(for fraction: Double) -> Color {
        Theme.severityColor(forFraction: fraction)
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
            // Match the adaptive height the manager baked into the window frame.
            let bodyHeight = hostState.frames.map { $0.expanded.height - geometry.menuBarHeight }
            return NotchGeometryCalculator.hostedSurfaceLayout(
                screenFrame: screenFrame,
                geometry: geometry,
                expansionProgress: hostState.expansionProgress,
                expandedHeight: bodyHeight
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
        // The expanded body now uses a fixed content scale (widgetSizeScale)
        // with internal scrolling, so the surface scale only needs to stay
        // stable; content no longer stretches to fill the panel height.
        widgetSizeScale
    }

    // MARK: - Status

    private var collapsedStatus: NotchCollapsedStatusDisplay {
        NotchCollapsedStatusEngine.value(
            widgets: store.widgets.map(\.descriptor),
            state: watcher.effectiveState,
            configuration: NotchCollapsedStatusConfiguration(
                leading: NotchCollapsedSourceStore.source(from: collapsedLeadingSource),
                trailing: NotchCollapsedSourceStore.source(from: collapsedTrailingSource)
            )
        )
    }
}
