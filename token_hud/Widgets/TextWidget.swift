// token_hud/Widgets/TextWidget.swift
import SwiftUI

struct TextWidget: View {
    let text: String
    let subtext: String?

    @Environment(\.panelAdaptiveScale) private var scale

    var body: some View {
        VStack(alignment: .center, spacing: 1 * scale) {
            Text(text)
                .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let sub = subtext {
                Text(sub)
                    .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.56))
                    .lineLimit(1)
            }
        }
    }
}
