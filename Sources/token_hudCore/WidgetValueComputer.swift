// Sources/token_hudCore/WidgetValueComputer.swift
import Foundation

public enum WidgetValueComputer {

    public static func remainingValue(for quota: Quota) -> Double {
        (quota.total ?? 0) - quota.used
    }

    public static func usageFraction(for quota: Quota) -> Double {
        guard let total = quota.total, total > 0 else { return 0 }
        return quota.used / total
    }

    public static func formattedRemaining(quota: Quota) -> String {
        // For quotas with no cap, show the used amount instead of remaining
        guard quota.total != nil else {
            return formattedUsed(quota: quota)
        }
        let remaining = remainingValue(for: quota)
        switch quota.type {
        case .time:
            return formatSeconds(remaining)
        case .money:
            return String(format: "$%.2f", remaining)
        case .tokens:
            return formatTokens(remaining)
        case .requests:
            return String(Int(remaining))
        }
    }

    /// Format the used amount (for quotas with no hard cap).
    public static func formattedUsed(quota: Quota) -> String {
        switch quota.type {
        case .time:     return formatSeconds(quota.used)
        case .money:    return String(format: "$%.2f", quota.used)
        case .tokens:   return formatTokens(quota.used)
        case .requests: return String(Int(quota.used))
        }
    }

    public static func formattedSessionTokens(_ session: SessionSnapshot?) -> String {
        guard let t = session?.tokens else { return "—" }
        return formatTokens(t)
    }

    public static func countdownString(to resetsAt: String) -> String? {
        let fmt = ISO8601DateFormatter()
        guard let date = fmt.date(from: resetsAt) else { return nil }
        let secs = date.timeIntervalSinceNow
        guard secs > 0 else { return "↺ now" }
        return "↺ " + formatSeconds(secs)
    }

    // MARK: - Private helpers

    private static func formatSeconds(_ secs: Double) -> String {
        let total = Int(secs)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private static func formatTokens(_ t: Double) -> String {
        if t >= 1_000_000 { return String(format: "%.1fM", t / 1_000_000) }
        if t >= 1_000 {
            let k = t / 1_000
            return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return String(Int(t))
    }
}
