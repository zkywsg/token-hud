// Sources/token_hudCore/WidgetValueComputer.swift
import Foundation

public enum WidgetValueComputer {
    public struct ValueWithDetail: Equatable, Sendable {
        public let value: String
        public let detail: String?

        public init(value: String, detail: String?) {
            self.value = value
            self.detail = detail
        }
    }

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
        case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens:
            return formatTokens(remaining)
        case .dailyRequests, .monthlyRequests:
            return String(Int(remaining))
        case .costSpent:
            return String(format: "$%.2f", remaining)
        }
    }

    public static func formattedCredits(_ credits: Double?) -> String {
        guard let credits else { return "—" }
        return formatTokens(credits)
    }

    public static func formattedMiMoTokenPlanExpiry(_ service: Service?) -> String {
        guard let service else { return "—" }
        if service.error == "Console login expired" {
            return "登录过期"
        }
        guard let resetsAt = service.quotas.first(where: { $0.unit.lowercased() == "credits" })?.resetsAt else {
            return "无到期时间"
        }
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: resetsAt) else {
            return "无到期时间"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    public static func codexRateLimitDisplay(_ quota: Quota, now: Date = Date()) -> ValueWithDetail {
        let remaining = 1.0 - usageFraction(for: quota)
        let label = codexRateLimitWindowLabel(quota)
        let value = String(format: "%.0f%% %@", remaining * 100, label)
        let detail = quota.resetsAt.flatMap { countdownString(to: $0, now: now) }
        return ValueWithDetail(value: value, detail: detail)
    }

    public static func codexSubscriptionStatus(_ service: Service?) -> String {
        guard let service else { return "未连接" }
        if service.error != nil { return "异常" }
        let plan = service.label
            .replacingOccurrences(of: "Codex", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let planName = plan.isEmpty ? "Codex" : plan
        return "\(planName) 已订阅"
    }

    public static func codexServiceLabel(plan: String?) -> String {
        guard let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines),
              !plan.isEmpty,
              plan.lowercased() != "unknown"
        else { return "Codex" }
        return "Codex \(plan.capitalized)"
    }

    private static func codexRateLimitWindowLabel(_ quota: Quota) -> String {
        let seconds = Int(quota.total ?? 0)
        if seconds >= 604_800 { return "7day" }
        if seconds >= 18_000 { return "5 hours" }
        return "limit"
    }

    /// Format the used amount (for quotas with no hard cap).
    public static func formattedUsed(quota: Quota) -> String {
        switch quota.type {
        case .time:     return formatSeconds(quota.used)
        case .money:    return String(format: "$%.2f", quota.used)
        case .tokens:   return formatTokens(quota.used)
        case .requests: return String(Int(quota.used))
        case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens:
            return formatTokens(quota.used)
        case .dailyRequests, .monthlyRequests:
            return String(Int(quota.used))
        case .costSpent:
            return String(format: "$%.2f", quota.used)
        }
    }

    public static func formattedSessionTokens(_ session: SessionSnapshot?) -> String {
        guard let t = session?.tokens else { return "—" }
        return formatTokens(t)
    }

    public static func formattedInputTokens(_ session: SessionSnapshot?) -> String {
        guard let t = session?.inputTokens else { return "—" }
        return formatTokens(t)
    }

    public static func formattedOutputTokens(_ session: SessionSnapshot?) -> String {
        guard let t = session?.outputTokens else { return "—" }
        return formatTokens(t)
    }

    public static func formattedCostSpent(_ session: SessionSnapshot?) -> String {
        guard let c = session?.costSpent else { return "—" }
        return String(format: "$%.2f", c)
    }

    public static func countdownString(to resetsAt: String) -> String? {
        countdownString(to: resetsAt, now: Date())
    }

    public static func countdownString(to resetsAt: String, now: Date) -> String? {
        let fmt = ISO8601DateFormatter()
        guard let date = fmt.date(from: resetsAt) else { return nil }
        let secs = date.timeIntervalSince(now)
        guard secs > 0 else { return "↺ now" }
        return "↺ " + formatSeconds(secs)
    }

    // MARK: - Derived metrics

    public static func sessionDurationSeconds(from session: SessionSnapshot) -> Double {
        let fmt = ISO8601DateFormatter()
        guard let start = fmt.date(from: session.startedAt) else { return 0 }
        return max(0, Date().timeIntervalSince(start))
    }

    public static func sessionDuration(from session: SessionSnapshot) -> String {
        formatSeconds(sessionDurationSeconds(from: session))
    }

    public static func tokensPerMinute(from session: SessionSnapshot) -> String {
        let duration = sessionDurationSeconds(from: session)
        guard duration > 60, let tokens = session.tokens else { return "—" }
        let rate = tokens / (duration / 60)
        if rate >= 1000 { return String(format: "%.1fk/min", rate / 1000) }
        return String(format: "%.0f/min", rate)
    }

    public static func inputOutputRatio(from session: SessionSnapshot) -> String {
        guard let input = session.inputTokens, let output = session.outputTokens, output > 0 else { return "—" }
        let ratio = input / output
        return String(format: "%.1f:1", ratio)
    }

    public static func costPerRequest(from session: SessionSnapshot) -> String {
        guard let cost = session.costSpent, let reqs = session.requests, reqs > 0 else { return "—" }
        return String(format: "$%.2f", cost / reqs)
    }

    public static func formattedModelTokens(_ usage: ModelUsage) -> String {
        let total = (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
        return formatTokens(total)
    }

    public static func formattedModelCost(_ usage: ModelUsage) -> String {
        guard let cost = usage.costSpent else { return "—" }
        return String(format: "$%.2f", cost)
    }

    // MARK: - Private helpers

    private static func formatSeconds(_ secs: Double) -> String {
        let total = Int(secs)
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
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
