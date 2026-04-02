// token_hud/Overlay/RightSideView.swift
import SwiftUI

struct RightSideView: View {
    @Environment(StateWatcher.self) private var watcher
    @Environment(WidgetStore.self)  private var store

    var body: some View {
        HStack(spacing: 4) {
            ForEach(store.rightWidgets) { config in
                WidgetRenderer(config: config, state: watcher.currentState)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
    }
}
