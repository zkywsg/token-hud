import SwiftUI

/// Expanded view: single full-width panel with ears at top (menu bar area)
/// and content body extending downward. Panel top is at screen.maxY.
struct NotchExpandedView: View {
    @Environment(NotchHostState.self) private var hostState
    @Environment(WidgetStore.self) private var store
    @Environment(StateWatcher.self) private var watcher
    @AppStorage("overlayMode") private var overlayMode = "compact"

    var body: some View {
        GeometryReader { geo in
            let adaptiveScale = calculateAdaptiveScale(for: geo.size)

            VStack(spacing: 0) {
                // Body: content area below notch
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: NotchGeometryCalculator.expandedBottomCornerRadius,
                        bottomTrailingRadius: NotchGeometryCalculator.expandedBottomCornerRadius,
                        topTrailingRadius: 0
                    )
                    .fill(Color.black.opacity(0.92))
                )

                // Ears: cover menu bar on each side of notch
                NotchEarView()
            }
            .environment(\.panelAdaptiveScale, adaptiveScale)
        }
    }

    private func calculateAdaptiveScale(for size: CGSize) -> CGFloat {
        let menuBarH = hostState.geometry?.menuBarHeight ?? 24
        let contentHeight = size.height - menuBarH
        let baseHeight: CGFloat = 60
        let idealHeight: CGFloat
        if overlayMode == "grouped" {
            let serviceCount = Set(store.widgets.map(\.service)).count
            idealHeight = max(baseHeight, CGFloat(serviceCount) * 32 + 16)
        } else {
            idealHeight = baseHeight
        }
        return (contentHeight / idealHeight).clamped(to: 0.5...3.0)
    }
}
