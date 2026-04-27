import SwiftUI

struct FloatingPanelView: View {
    @Environment(StateWatcher.self) private var watcher
    @Environment(WidgetStore.self) private var store
    @AppStorage("floatingPanelScale") private var scale = 1.0
    @AppStorage("overlayMode") private var overlayMode = "compact"
    @State private var gestureStartScale: CGFloat = 1.0

    var body: some View {
        Group {
            if overlayMode == "grouped" {
                GroupedOverlayView(
                    widgets: store.widgets,
                    state: watcher.effectiveState
                )
                .padding(12)
            } else {
                compactOverlay
            }
        }
        .fixedSize()
        .scaleEffect(scale, anchor: .center)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = (gestureStartScale * value)
                        .clamped(to: 0.5...3.0)
                }
                .onEnded { _ in
                    gestureStartScale = scale
                }
        )
        .onAppear { gestureStartScale = scale }
    }

    private var compactOverlay: some View {
        HStack(spacing: 6) {
            ForEach(store.widgets) { config in
                WidgetRenderer(config: config, state: watcher.effectiveState, showServiceLabel: true)
            }
        }
        .padding(12)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
