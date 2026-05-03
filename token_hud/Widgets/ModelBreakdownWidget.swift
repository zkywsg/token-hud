import SwiftUI

struct ModelBreakdownWidget: View {
    let service: Service?

    @Environment(\.panelAdaptiveScale) private var scale

    private var models: [ModelUsage] {
        service?.currentSession?.modelBreakdown ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            if models.isEmpty {
                Text("无数据")
                    .font(.system(size: 9 * scale, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                ForEach(Array(models.prefix(4).enumerated()), id: \.offset) { _, usage in
                    HStack(spacing: 4 * scale) {
                        Text(shortModelName(usage.model))
                            .font(.system(size: 8 * scale, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .frame(minWidth: 40 * scale, alignment: .leading)
                        Spacer()
                        Text(WidgetValueComputer.formattedModelTokens(usage))
                            .font(.system(size: 8 * scale, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text(WidgetValueComputer.formattedModelCost(usage))
                            .font(.system(size: 8 * scale, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 4 * scale)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6 * scale))
    }

    private func shortModelName(_ name: String) -> String {
        let parts = name.split(separator: "-")
        if parts.count >= 3 {
            let middle = parts.dropFirst().dropLast()
            if middle.isEmpty { return name }
            return middle.joined(separator: "-")
        }
        return name
    }
}
