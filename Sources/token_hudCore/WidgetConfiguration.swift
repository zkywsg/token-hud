import Foundation

public struct WidgetDescriptor: Codable, Identifiable, Sendable {
    public var id: String
    public var service: String
    public var metric: String
    public var style: String
    public var quotaIndex: Int

    public init(
        id: String? = nil,
        service: String,
        metric: String,
        style: String,
        quotaIndex: Int = 0
    ) {
        self.service = service
        self.metric = metric
        self.style = style
        self.quotaIndex = quotaIndex
        self.id = id ?? "\(service):\(metric):\(style):\(quotaIndex)"
    }

    public var semanticKey: String {
        "\(service)|\(metric)|\(style)|\(quotaIndex)"
    }
}

extension WidgetDescriptor: Equatable {
    public static func == (lhs: WidgetDescriptor, rhs: WidgetDescriptor) -> Bool {
        lhs.service == rhs.service &&
            lhs.metric == rhs.metric &&
            lhs.style == rhs.style &&
            lhs.quotaIndex == rhs.quotaIndex
    }
}

public enum WidgetRecommendationEngine {
    public static func recommendations(
        for snapshot: ProviderCredentialSnapshot,
        state: StateFile? = nil,
        includeCodexLocalAuth: Bool = true
    ) -> [WidgetDescriptor] {
        var result: [WidgetDescriptor] = []

        if snapshot.claudeSessionKey != nil {
            result.append(contentsOf: [
                WidgetDescriptor(service: "claude", metric: "remaining_time", style: "bar"),
                WidgetDescriptor(service: "claude", metric: "session_tokens", style: "text")
            ])
        }

        if includeCodexLocalAuth {
            result.append(contentsOf: [
                WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 0),
                WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 1),
                WidgetDescriptor(service: "codex", metric: "subscription_status", style: "text")
            ])
        }

        if snapshot.apiKeys["deepseek"] != nil {
            result.append(WidgetDescriptor(service: "deepseek", metric: "balance", style: "text"))
        }

        if hasMiniMaxTokenPlanEvidence(in: state) {
            result.append(contentsOf: [
                WidgetDescriptor(service: "minimax", metric: "monthly_tokens", style: "bar"),
                WidgetDescriptor(service: "minimax", metric: "usage_percent", style: "text")
            ])
        }

        if snapshot.hasMiMoTokenPlanCredential {
            result.append(contentsOf: [
                WidgetDescriptor(service: "mimo", metric: "credits_used", style: "bar"),
                WidgetDescriptor(service: "mimo", metric: "plan_name", style: "text"),
                WidgetDescriptor(service: "mimo", metric: "reset_countdown", style: "text")
            ])
        }

        return result
    }

    private static func hasMiniMaxTokenPlanEvidence(in state: StateFile?) -> Bool {
        guard let service = state?.services["minimax"] else { return false }
        return service.quotas.contains { quota in
            switch quota.type {
            case .time, .tokens, .money, .requests,
                 .dailyTokens, .monthlyTokens,
                 .dailyRequests, .monthlyRequests:
                return (quota.total ?? 0) > 0 || quota.used > 0
            case .inputTokens, .outputTokens, .costSpent:
                return false
            }
        }
    }

    public static func supplement(
        existing: [WidgetDescriptor],
        with recommended: [WidgetDescriptor]
    ) -> [WidgetDescriptor] {
        var seen = Set(existing.map(\.semanticKey))
        var result = existing
        for descriptor in recommended where !seen.contains(descriptor.semanticKey) {
            result.append(descriptor)
            seen.insert(descriptor.semanticKey)
        }
        return result
    }
}

public enum NotchCollapsedSource: Codable, Equatable, Sendable {
    case auto
    case widget(String)
    case metric(service: String, metric: String, quotaIndex: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case widgetID
        case service
        case metric
        case quotaIndex
    }

    private enum Kind: String, Codable {
        case auto
        case widget
        case metric
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .auto:
            self = .auto
        case .widget:
            self = .widget(try container.decode(String.self, forKey: .widgetID))
        case .metric:
            self = .metric(
                service: try container.decode(String.self, forKey: .service),
                metric: try container.decode(String.self, forKey: .metric),
                quotaIndex: try container.decodeIfPresent(Int.self, forKey: .quotaIndex) ?? 0
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode(Kind.auto, forKey: .kind)
        case .widget(let widgetID):
            try container.encode(Kind.widget, forKey: .kind)
            try container.encode(widgetID, forKey: .widgetID)
        case .metric(let service, let metric, let quotaIndex):
            try container.encode(Kind.metric, forKey: .kind)
            try container.encode(service, forKey: .service)
            try container.encode(metric, forKey: .metric)
            try container.encode(quotaIndex, forKey: .quotaIndex)
        }
    }
}

public struct NotchCollapsedStatusConfiguration: Codable, Equatable, Sendable {
    public var leading: NotchCollapsedSource
    public var trailing: NotchCollapsedSource

    public init(leading: NotchCollapsedSource = .auto, trailing: NotchCollapsedSource = .auto) {
        self.leading = leading
        self.trailing = trailing
    }

    public static let automatic = NotchCollapsedStatusConfiguration()
}

public struct NotchCollapsedStatusDisplay: Equatable, Sendable {
    public let leadingFraction: Double
    public let trailingText: String

    public init(leadingFraction: Double, trailingText: String) {
        self.leadingFraction = leadingFraction
        self.trailingText = trailingText
    }
}

public enum NotchCollapsedStatusEngine {
    public static func value(
        widgets: [WidgetDescriptor],
        state: StateFile,
        configuration: NotchCollapsedStatusConfiguration = .automatic
    ) -> NotchCollapsedStatusDisplay {
        let automatic = automaticFraction(widgets: widgets, state: state) ?? 0
        let leading = fraction(for: configuration.leading, widgets: widgets, state: state) ?? automatic
        let trailing = fraction(for: configuration.trailing, widgets: widgets, state: state) ?? automatic
        return NotchCollapsedStatusDisplay(
            leadingFraction: leading,
            trailingText: percentText(for: trailing)
        )
    }

    private static func automaticFraction(widgets: [WidgetDescriptor], state: StateFile) -> Double? {
        for widget in widgets {
            if let value = fraction(for: widget, state: state) {
                return value
            }
        }
        for service in state.services.values {
            if let quota = service.quotas.first(where: { ($0.total ?? 0) > 0 }) {
                return WidgetValueComputer.usageFraction(for: quota)
            }
        }
        return nil
    }

    private static func fraction(
        for source: NotchCollapsedSource,
        widgets: [WidgetDescriptor],
        state: StateFile
    ) -> Double? {
        switch source {
        case .auto:
            return automaticFraction(widgets: widgets, state: state)
        case .widget(let widgetID):
            guard let widget = widgets.first(where: { $0.id == widgetID }) else { return nil }
            return fraction(for: widget, state: state)
        case .metric(let service, let metric, let quotaIndex):
            return fraction(
                for: WidgetDescriptor(service: service, metric: metric, style: "bar", quotaIndex: quotaIndex),
                state: state
            )
        }
    }

    private static func fraction(for descriptor: WidgetDescriptor, state: StateFile) -> Double? {
        guard let service = state.services[descriptor.service] else { return nil }

        switch descriptor.metric {
        case "remaining_time":
            return quotaFraction(type: .time, service: service, descriptor: descriptor)
                ?? creditFraction(service: service)
        case "tokens_remaining", "usage_percent":
            return quotaFraction(type: .tokens, service: service, descriptor: descriptor)
                ?? creditFraction(service: service)
        case "balance":
            return quotaFraction(type: .money, service: service, descriptor: descriptor)
        case "daily_tokens":
            return quotaFraction(type: .dailyTokens, service: service, descriptor: descriptor)
        case "monthly_tokens":
            return quotaFraction(type: .monthlyTokens, service: service, descriptor: descriptor)
        case "daily_requests":
            return quotaFraction(type: .dailyRequests, service: service, descriptor: descriptor)
        case "monthly_requests":
            return quotaFraction(type: .monthlyRequests, service: service, descriptor: descriptor)
        case "credits_remaining", "credits_used", "session_credits":
            return creditFraction(service: service)
        case "subscription_status":
            return service.error == nil ? 1 : 0
        default:
            return firstQuotaFraction(service: service)
        }
    }

    private static func quotaFraction(
        type: QuotaType,
        service: Service,
        descriptor: WidgetDescriptor
    ) -> Double? {
        let matching = service.quotas.filter { $0.type == type }
        guard !matching.isEmpty else { return nil }
        let quota = descriptor.quotaIndex < matching.count ? matching[descriptor.quotaIndex] : matching[0]
        guard (quota.total ?? 0) > 0 else { return nil }
        return WidgetValueComputer.usageFraction(for: quota)
    }

    private static func creditFraction(service: Service) -> Double? {
        guard let quota = service.quotas.first(where: { $0.unit.lowercased() == "credits" }),
              (quota.total ?? 0) > 0
        else { return nil }
        return WidgetValueComputer.usageFraction(for: quota)
    }

    private static func firstQuotaFraction(service: Service) -> Double? {
        guard let quota = service.quotas.first(where: { ($0.total ?? 0) > 0 }) else { return nil }
        return WidgetValueComputer.usageFraction(for: quota)
    }

    private static func percentText(for fraction: Double) -> String {
        "\(Int((fraction.clamped(to: 0...1) * 100).rounded()))%"
    }
}
