import SwiftUI

struct StatusWidget: View {
    let fraction: Double
    let label: String

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
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(statusText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}
