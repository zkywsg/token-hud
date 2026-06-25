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
    @AppStorage("notchCollapsedLeadingSource") private var collapsedLeadingSource = NotchCollapsedSourceStore.autoRawValue
    @AppStorage("notchCollapsedTrailingSource") private var collapsedTrailingSource = NotchCollapsedSourceStore.autoRawValue

    var body: some View {
        GeometryReader { geo in
            let layout = surfaceLayout(in: geo.size)
            let status = collapsedStatus
            let adaptiveScale = hostState.expandedContentScale

            ZStack(alignment: .topLeading) {
                bodyPanel(layout.body, opacity: layout.contentOpacity, adaptiveScale: adaptiveScale, layout: layout)
                topCap(layout.topCap, bodyHeight: layout.body.height, layout: layout)
                statusSlot(layout.leftStatusSlot, isLeading: true, status: status, scale: adaptiveScale, layout: layout)
                statusSlot(layout.rightStatusSlot, isLeading: false, status: status, scale: adaptiveScale, layout: layout)
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
                .fill(Color.black)
            capShape
                .stroke(Color.white.opacity(bodyHeight > 0.5 ? 0.16 : 0.12), lineWidth: 0.7)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: topY)
    }

    @ViewBuilder
    private func statusSlot(
        _ rect: CGRect,
        isLeading: Bool,
        status: NotchCollapsedStatusDisplay,
        scale: CGFloat,
        layout: NotchHostedSurfaceLayout
    ) -> some View {
        if rect.width > 1 {
            let topY = topOffset(for: rect, in: layout)
            let earOpacity = CGFloat(NotchInfoEarPresentationPolicy.opacity(
                contentOpacity: Double(layout.contentOpacity)
            ))
            let progressWidth = CGFloat(NotchInfoEarPresentationPolicy.progressWidth(
                slotWidth: Double(rect.width)
            ))

            if isLeading {
                infoEarContainer(rect: rect, layout: layout) {
                    progressBar(fraction: status.leadingFraction)
                        .frame(width: progressWidth, height: 5)
                }
                    .offset(x: rect.minX, y: topY)
                    .opacity(earOpacity)
            } else {
                infoEarContainer(rect: rect, layout: layout) {
                    if NotchInfoEarPresentationPolicy.showsText(
                        slotWidth: Double(rect.width),
                        text: status.trailingText
                    ) {
                        Text(status.trailingText)
                            .font(.system(size: 10.5 * scale, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.90))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .truncationMode(.tail)
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.32))
                            .frame(width: min(18, max(8, rect.width - 18)), height: 5)
                    }
                }
                    .offset(x: rect.minX, y: topY)
                    .opacity(earOpacity)
            }
        }
    }

    private func infoEarContainer<Content: View>(
        rect: CGRect,
        layout: NotchHostedSurfaceLayout,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let expandedAmount = CGFloat(layout.contentOpacity)
        let horizontalInset = max(3, min(6, rect.width * 0.12))
        let verticalInset: CGFloat = expandedAmount > 0.05 ? 5 : 4
        let cornerRadius = max(6, (rect.height - verticalInset * 2) / 2)
        let backgroundOpacity = max(0.04, 0.10 - 0.04 * expandedAmount)
        let strokeOpacity = max(0.08, 0.14 - 0.04 * expandedAmount)

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(backgroundOpacity))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.7)
            content()
                .padding(.horizontal, 4)
        }
        .frame(
            width: max(12, rect.width - horizontalInset * 2),
            height: max(10, rect.height - verticalInset * 2),
            alignment: .center
        )
        .frame(width: rect.width, height: rect.height, alignment: .center)
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
            panelShape
                .fill(Color.black)
            panelShape
                .stroke(Color.white.opacity(0.14 * opacity), lineWidth: 0.8)
                .shadow(color: Color.black.opacity(0.30 * opacity), radius: 18, y: 10)

            if NotchHostedBodyPresentationPolicy.shouldRenderExpandedContent(
                bodyHeight: Double(rect.height),
                contentOpacity: Double(opacity)
            ) {
                Group {
                    if hostState.expandedAllowsVerticalScrolling {
                        ScrollView(.vertical, showsIndicators: false) {
                            expandedContent
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .scrollClipDisabled(false)
                    } else {
                        expandedContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: overlayMode)
                .animation(.easeInOut(duration: 0.2), value: hostState.expandedLayoutMode)
                .padding(.horizontal, 12 * adaptiveScale)
                .padding(.top, OverlayModelCardStyle.hostedBodyTopInset(scale: adaptiveScale))
                .padding(.bottom, max(8, 8 * adaptiveScale))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(opacity)
                .scaleEffect(0.98 + 0.02 * opacity)
            }
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
                expansionProgress: hostState.expansionProgress,
                expandedBodyHeight: hostState.expandedBodyHeight
            )
        }
        let fallbackScreen = CGRect(origin: .zero, size: size)
        let fallbackGeometry = NotchGeometryCalculator.noNotchFallback(screenFrame: fallbackScreen)
        return NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: fallbackScreen,
            geometry: fallbackGeometry,
            expansionProgress: hostState.expansionProgress,
            expandedBodyHeight: hostState.expandedBodyHeight
        )
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

private extension NotchHostedSurfaceView {
    @ViewBuilder
    var expandedContent: some View {
        if hostState.expandedLayoutMode == .sectioned {
            SectionedOverlayView(widgets: store.widgets, state: watcher.effectiveState)
                .transition(.opacity)
        } else if overlayMode == "grouped" {
            GroupedOverlayView(
                widgets: store.widgets,
                state: watcher.effectiveState
            )
            .transition(.opacity)
        } else {
            CompactOverlayContent()
                .transition(.opacity)
        }
    }
}
