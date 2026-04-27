import SwiftUI

struct ModelBreakdownWidget: View {
    let service: Service?

    private var models: [ModelUsage] {
        service?.currentSession?.modelBreakdown ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if models.isEmpty {
                Text("无数据")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                ForEach(Array(models.prefix(4).enumerated()), id: \.offset) { _, usage in
                    HStack(spacing: 4) {
                        Text(shortModelName(usage.model))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .frame(minWidth: 40, alignment: .leading)
                        Spacer()
                        Text(WidgetValueComputer.formattedModelTokens(usage))
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text(WidgetValueComputer.formattedModelCost(usage))
                            .font(.system(size: 8, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
