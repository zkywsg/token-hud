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
                .foregroundColor(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
