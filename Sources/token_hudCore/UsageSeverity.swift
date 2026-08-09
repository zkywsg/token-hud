// Sources/token_hudCore/UsageSeverity.swift

/// Single source of truth for turning a usage fraction (0...1, where higher
/// means more consumed) into a severity level. Both the collapsed notch strip
/// and the expanded usage bars map their green/yellow/red treatment through
/// this so a given usage never reads as two different severities.
public enum UsageSeverity: Sendable, Equatable {
    /// Comfortable headroom.
    case ok
    /// Getting close to the limit — worth a glance.
    case warn
    /// Nearly exhausted — needs attention.
    case critical

    /// Warning turns on at 65% consumed, critical at 85%.
    public static let warnThreshold = 0.65
    public static let criticalThreshold = 0.85

    /// Maps a usage fraction to its severity. Values are clamped so callers
    /// don't have to guard against out-of-range input.
    public static func forFraction(_ fraction: Double) -> UsageSeverity {
        let value = min(1, max(0, fraction))
        if value >= criticalThreshold { return .critical }
        if value >= warnThreshold { return .warn }
        return .ok
    }
}
