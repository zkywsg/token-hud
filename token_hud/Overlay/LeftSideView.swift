// token_hud/Overlay/LeftSideView.swift
import SwiftUI

struct LeftSideView: View {
    @Environment(StateWatcher.self) private var watcher
    @Environment(WidgetStore.self)  private var store

    var body: some View {
        HStack(spacing: 4) {
            ForEach(store.leftWidgets) { config in
                // WidgetRenderer will replace this in Task 8
                PlaceholderWidgetView(label: config.metric.rawValue)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
    }
}

struct PlaceholderWidgetView: View {
    let label: String
    var body: some View {
        Text("●")
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.7))
    }
}
