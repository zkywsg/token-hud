import SwiftUI

/// Hosted notch UI drawn inside a transparent full-width panel.
struct NotchFusionView: View {
    @Environment(NotchHostState.self) private var hostState
    @Environment(WidgetStore.self) private var store
    @Environment(StateWatcher.self) private var watcher
    @AppStorage("overlayMode") private var overlayMode = "compact"

    var body: some View {
        GeometryReader { geo in
            let layout = fusionLayout(fallbackSize: geo.size)
            let adaptiveScale = calculateAdaptiveScale(for: layout.body.size)

            ZStack(alignment: .topLeading) {
                topBridge(layout.topBridge)
                bodyPanel(layout.body, contentOpacity: layout.contentOpacity, adaptiveScale: adaptiveScale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(\.panelAdaptiveScale, adaptiveScale)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hostState.expansionProgress)
    }

    private func topBridge(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.96))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func bodyPanel(_ rect: CGRect, contentOpacity: CGFloat, adaptiveScale: CGFloat) -> some View {
        let bottomRadius = min(16, rect.height / 2)
        return ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: bottomRadius,
                bottomTrailingRadius: bottomRadius,
                topTrailingRadius: 0
            )
            .fill(Color.black.opacity(0.96))
            .shadow(color: Color.black.opacity(0.24 * contentOpacity), radius: 18, y: 10)

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
            .opacity(contentOpacity)
            .scaleEffect(0.98 + 0.02 * contentOpacity)
        }
        .frame(width: rect.width, height: rect.height)
        .clipped()
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(hostState.isExpanded)
    }

    private func fusionLayout(fallbackSize: CGSize) -> NotchFusionLayout {
        guard let geometry = hostState.geometry else {
            let fallbackScreen = CGRect(origin: .zero, size: fallbackSize)
            let fallbackGeometry = NotchGeometryCalculator.noNotchFallback(screenFrame: fallbackScreen)
            return NotchGeometryCalculator.notchFusionLayout(
                screenFrame: fallbackScreen,
                geometry: fallbackGeometry,
                expansionProgress: hostState.expansionProgress
            )
        }

        if !geometry.hasNotch {
            let fallbackScreen = CGRect(origin: .zero, size: fallbackSize)
            let fallbackGeometry = NotchGeometryCalculator.noNotchFallback(screenFrame: fallbackScreen)
            return NotchGeometryCalculator.notchFusionLayout(
                screenFrame: fallbackScreen,
                geometry: fallbackGeometry,
                expansionProgress: hostState.expansionProgress
            )
        }

        let screenFrame = CGRect(origin: .zero, size: fallbackSize)

        return NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screenFrame,
            geometry: geometry,
            expansionProgress: hostState.expansionProgress
        )
    }

    private func calculateAdaptiveScale(for size: CGSize) -> CGFloat {
        let baseHeight: CGFloat = 60
        let idealHeight: CGFloat
        if overlayMode == "grouped" {
            let serviceCount = Set(store.widgets.map(\.service)).count
            idealHeight = max(baseHeight, CGFloat(serviceCount) * 32 + 16)
        } else {
            idealHeight = baseHeight
        }
        return (size.height / idealHeight).clamped(to: 0.5...3.0)
    }
}
