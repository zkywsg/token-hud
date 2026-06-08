import SwiftUI

struct StatusWidget: View {
    let fraction: Double
    let label: String

    @Environment(\.panelAdaptiveScale) private var scale

    private var color: Color {
        if fraction >= 0.8 { return Color(red: 1.0, green: 0.28, blue: 0.34) }
        if fraction >= 0.5 { return Color(red: 1.0, green: 0.76, blue: 0.20) }
        return Color(red: 0.30, green: 0.86, blue: 0.55)
    }

    private var statusText: String {
        if fraction >= 0.8 { return "警告" }
        if fraction >= 0.5 { return "注意" }
        return "正常"
    }

    var body: some View {
        HStack(spacing: 5 * scale) {
            Circle()
                .fill(color)
                .frame(width: 8 * scale, height: 8 * scale)
                .shadow(color: color.opacity(0.6), radius: 3 * scale)
            VStack(alignment: .leading, spacing: 0) {
                Text(statusText)
                    .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.94))
                Text(label)
                    .font(.system(size: 8 * scale, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.56))
            }
        }
    }
}
