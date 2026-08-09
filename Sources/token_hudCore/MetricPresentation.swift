// Sources/token_hudCore/MetricPresentation.swift

/// How a metric should be drawn, decided at *runtime* from whether the provider
/// actually reports a total — not hardcoded per metric.
///
/// The same metric can be either: `cost_spent` with a money quota has a real
/// denominator and deserves a gauge, while the same metric on a provider that
/// only reports spend has nothing to fill a gauge with. Drawing an empty bar in
/// that case reads as "nothing used yet" when the truth is "no limit known".
public enum MetricPresentation: Equatable, Sendable {
    /// A real `quota.total` exists; the fraction (0...1 consumed) is meaningful.
    case quota(Double)
    /// An unbounded counter — show the number, never a proportion.
    case counter
    /// A label or boolean; carries no magnitude at all.
    case status

    public var fraction: Double? {
        if case .quota(let f) = self { return f }
        return nil
    }

    public var showsGauge: Bool {
        if case .quota = self { return true }
        return false
    }
}

/// Metrics withdrawn from the picker.
///
/// The enum cases are deliberately **kept** so previously saved configurations
/// still decode — dropping a case would fail the whole widget array. Instead
/// these are filtered out of every selection surface and discarded on load.
public enum RetiredMetrics {
    /// Retired either because the value duplicated something the card already
    /// shows, or because its "percentage" came from a hardcoded denominator
    /// (session length ÷ 8h, tokens/min ÷ 200) rather than real data.
    public static let rawValues: Set<String> = [
        // Duplicated elsewhere on the card.
        "subscription_status",  // → badge on the card subtitle
        "plan_name",            // → already the card subtitle
        "reset_countdown",      // → already the reset pill
        // Invented denominators / low-signal derived stats.
        "session_duration",
        "tokens_per_minute",
        "input_output_ratio",
        "cost_per_request",
    ]

    public static func isRetired(_ rawValue: String) -> Bool {
        rawValues.contains(rawValue)
    }
}
