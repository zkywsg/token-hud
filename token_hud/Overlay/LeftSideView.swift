// token_hud/Overlay/LeftSideView.swift
import SwiftUI

struct LeftSideView: View {
    @Environment(StateWatcher.self) private var watcher
    @Environment(WidgetStore.self)  private var store

    var body: some View {
        HStack(spacing: 4) {
            ForEach(store.leftWidgets) { config in
                WidgetRenderer(config: config, state: watcher.effectiveState)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
    }
}
