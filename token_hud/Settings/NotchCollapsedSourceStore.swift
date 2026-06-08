import Foundation

enum NotchCollapsedSourceStore {
    static let autoRawValue = "auto"

    static func rawValue(for source: NotchCollapsedSource) -> String {
        switch source {
        case .auto:
            return autoRawValue
        case .widget(let id):
            return "widget:\(id)"
        case .metric(let service, let metric, let quotaIndex):
            return "metric:\(service):\(metric):\(quotaIndex)"
        }
    }

    static func source(from rawValue: String) -> NotchCollapsedSource {
        if rawValue == autoRawValue || rawValue.isEmpty {
            return .auto
        }
        if rawValue.hasPrefix("widget:") {
            return .widget(String(rawValue.dropFirst("widget:".count)))
        }
        if rawValue.hasPrefix("metric:") {
            let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { return .auto }
            return .metric(
                service: String(parts[1]),
                metric: String(parts[2]),
                quotaIndex: Int(parts[3]) ?? 0
            )
        }
        return .auto
    }

    static func title(for rawValue: String, widgets: [WidgetConfig], recommendations: [WidgetConfig]) -> String {
        switch source(from: rawValue) {
        case .auto:
            return "自动"
        case .widget(let id):
            if let widget = widgets.first(where: { $0.id.uuidString == id }) {
                return "\(displayName(for: widget.service)) · \(title(for: widget))"
            }
            return "已删除组件"
        case .metric(let service, let metric, let quotaIndex):
            if let widget = recommendations.first(where: {
                $0.service == service && $0.metric.rawValue == metric && $0.quotaIndex == quotaIndex
            }) {
                return "\(displayName(for: widget.service)) · \(title(for: widget))"
            }
            return "\(displayName(for: service)) · \(metric)"
        }
    }

    private static func displayName(for service: String) -> String {
        ProviderCapability.catalog[service]?.displayName ?? service
    }

    private static func title(for widget: WidgetConfig) -> String {
        if widget.service == "codex", widget.metric == .remainingTime {
            return widget.quotaIndex == 1 ? "7 天剩余量" : "5 小时剩余量"
        }
        if widget.service == "mimo", widget.metric == .resetCountdown {
            return "Token Plan 到期时间"
        }
        return widget.metric.displayName
    }
}
