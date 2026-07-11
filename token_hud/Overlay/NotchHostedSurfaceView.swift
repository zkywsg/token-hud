import SwiftUI

/// Unified hosted notch surface. Collapsed and expanded states share the
/// same view; visual transition is driven entirely by
/// `hostState.expansionProgress` so the window itself never resizes and
/// SwiftUI transitions don't cross-fade two different view hierarchies.
struct NotchHostedSurfaceView: View {
    @Environment(NotchHostState.self) private var hostState
    @Environment(WidgetStore.self) private var store
    @Environment(StateWatcher.self) private var watcher
    @AppStorage("overlayLayout") private var overlayLayoutRaw = OverlayLayout.summary.rawValue
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
        let capShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0
        )

        return ZStack {
            capShape
                .fill(.thinMaterial)
            capShape
                .fill(Color.black.opacity(0.90))
            capShape
                .stroke(Color.white.opacity(bodyHeight > 0.5 ? 0.06 : 0.10), lineWidth: 0.7)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: topY)
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

            if isLeading {
                progressBar(fraction: status.leadingFraction)
                    .frame(
                        width: max(24, min(42, rect.width - 14)),
                        height: 5
                    )
                    .frame(width: rect.width, height: rect.height, alignment: .center)
                    .offset(x: rect.minX, y: topY)
                    .opacity(1 - layout.contentOpacity)
            } else {
                Text(status.trailingText)
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
        let panelShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0
        )

        return ZStack {
            SolidPanelBackground(shape: panelShape, prominence: opacity)

            OverlayContentView(
                layout: OverlayLayout.from(overlayLayoutRaw),
                widgets: store.widgets,
                state: watcher.effectiveState,
                entranceState: hostState.isExpanded
            )
            .environment(\.panelAdaptiveScale, widgetSizeScale)
            .padding(.horizontal, 12 * widgetSizeScale)
            .padding(.vertical, 8 * widgetSizeScale)
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
