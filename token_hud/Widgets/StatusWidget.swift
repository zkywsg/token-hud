import SwiftUI

struct StatusWidget: View {
    let fraction: Double
    let label: String

    @Environment(\.panelAdaptiveScale) private var scale

    private var color: Color {
        if fraction >= 0.8 { return .red }
        if fraction >= 0.5 { return .yellow }
        return .green
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
                    .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 8 * scale, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}
