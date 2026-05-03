// token_hud/Widgets/AggregateWidget.swift
import SwiftUI

struct AggregateWidget: View {
    let icon: String    // SF Symbol name
    let value: String

    @Environment(\.panelAdaptiveScale) private var scale

    var body: some View {
        HStack(spacing: 2 * scale) {
            Image(systemName: icon)
                .font(.system(size: 8 * scale, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
