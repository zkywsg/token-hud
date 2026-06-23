import SwiftUI

struct CompactOverlayContent: View {
    @Environment(WidgetStore.self) private var store
    @Environment(StateWatcher.self) private var watcher
    @Environment(\.panelAdaptiveScale) private var scale

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OverlayModelCardStyle.widgetSpacing(scale: scale)) {
                ForEach(store.widgets) { config in
                    WidgetRenderer(config: config, state: watcher.effectiveState, showServiceLabel: true)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
