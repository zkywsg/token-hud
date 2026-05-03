import SwiftUI

struct MultiWidget: View {
    let service: Service?
    let config: WidgetConfig
    let state: StateFile?

    @Environment(\.panelAdaptiveScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            ForEach(subMetrics, id: \.label) { item in
                HStack(spacing: 4 * scale) {
                    Image(systemName: item.icon)
                        .font(.system(size: 7 * scale, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 10 * scale)
                    Text(item.label)
                        .font(.system(size: 8 * scale, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 28 * scale, alignment: .leading)
                    Text(item.value)
                        .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 4 * scale)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6 * scale))
    }

    private struct SubMetric {
        let label: String
        let value: String
        let icon: String
    }

    private var subMetrics: [SubMetric] {
        guard let svc = service else { return [] }
        let session = svc.currentSession

        switch config.metric {
        case .sessionTokens, .tokensRemaining:
            var items: [SubMetric] = []
            if session?.tokens != nil {
                items.append(SubMetric(label: "总计", value: WidgetValueComputer.formattedSessionTokens(session), icon: "text.bubble"))
            }
            if session?.inputTokens != nil {
                items.append(SubMetric(label: "输入", value: WidgetValueComputer.formattedInputTokens(session), icon: "arrow.down.circle"))
            }
            if session?.outputTokens != nil {
                items.append(SubMetric(label: "输出", value: WidgetValueComputer.formattedOutputTokens(session), icon: "arrow.up.circle"))
            }
            return items

        case .costSpent:
            var items: [SubMetric] = []
            if session?.costSpent != nil {
                items.append(SubMetric(label: "会话", value: WidgetValueComputer.formattedCostSpent(session), icon: "dollarsign.circle.fill"))
            }
            if let q = svc.quotas.first(where: { $0.type == .money }) {
                items.append(SubMetric(label: "余额", value: WidgetValueComputer.formattedRemaining(quota: q), icon: "dollarsign.circle"))
            }
            if session?.requests != nil, session?.costSpent != nil {
                items.append(SubMetric(label: "单次", value: WidgetValueComputer.costPerRequest(from: session!), icon: "dollarsign.arrow.circlepath"))
            }
            return items

        case .tokensPerMinute:
            var items: [SubMetric] = []
            items.append(SubMetric(label: "速率", value: WidgetValueComputer.tokensPerMinute(from: session!), icon: "bolt.fill"))
            if session?.tokens != nil {
                items.append(SubMetric(label: "总计", value: WidgetValueComputer.formattedSessionTokens(session), icon: "text.bubble"))
            }
            items.append(SubMetric(label: "时长", value: WidgetValueComputer.sessionDuration(from: session!), icon: "timer"))
            return items

        case .creditsRemaining, .creditsUsed, .sessionCredits:
            var items: [SubMetric] = []
            if let q = svc.quotas.first(where: { $0.unit.lowercased() == "credits" }) {
                items.append(SubMetric(label: "已用", value: WidgetValueComputer.formattedCredits(q.used), icon: "chart.pie"))
                items.append(SubMetric(label: "剩余", value: WidgetValueComputer.formattedCredits(WidgetValueComputer.remainingValue(for: q)), icon: "creditcard"))
            }
            if session?.tokens != nil {
                items.append(SubMetric(label: "会话", value: WidgetValueComputer.formattedCredits(session?.tokens), icon: "sum"))
            }
            return items

        default:
            guard session?.tokens != nil else { return [] }
            return [SubMetric(label: "Token", value: WidgetValueComputer.formattedSessionTokens(session), icon: "text.bubble")]
        }
    }
}
