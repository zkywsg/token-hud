// token_hud/Widgets/BarWidget.swift
import SwiftUI

struct BarWidget: View {
    let fraction: Double   // 0.0 – 1.0 (used/total)
    let label: String
    var detail: String? = nil
    let width: CGFloat

    @Environment(\.panelAdaptiveScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(label)
                .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2 * scale)
                        .fill(Color.white.opacity(0.13))
                        .frame(height: 4 * scale)

                    RoundedRectangle(cornerRadius: 2 * scale)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(min(max(1.0 - fraction, 0), 1.0)), height: 4 * scale)
                        .animation(.easeOut(duration: 0.3), value: fraction)
                }
            }
            .frame(height: 4 * scale)

            if let detail {
                Text(detail)
                    .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: width)
    }

    private var barColor: Color {
        // fraction is usage; bar width = 1 - fraction. Color by actual usage.
        let usage = 1 - fraction
        switch usage {
        case 0..<0.5:   return Color(red: 0.30, green: 0.86, blue: 0.55)
        case 0..<0.8:   return Color(red: 1.0, green: 0.76, blue: 0.20)
        default:         return Color(red: 1.0, green: 0.28, blue: 0.34)
        }
    }
}
