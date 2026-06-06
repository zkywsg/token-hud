// Sources/token_hudCore/CodexJWT.swift
import Foundation

/// Decode the payload segment of a JWT. Returns nil on any parse failure.
/// The signature is NOT verified — for display/expiry use only.
public func decodeJWTPayload(_ token: String) -> [String: Any]? {
    let parts = token.components(separatedBy: ".")
    guard parts.count == 3 else { return nil }
    var b64 = parts[1]
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let rem = b64.count % 4
    if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
    guard
        let data = Data(base64Encoded: b64),
        let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj
}

/// Returns true if the token is expired or within `buffer` seconds of expiry,
/// or if the exp claim cannot be decoded.
public func isCodexTokenExpired(token: String, buffer: TimeInterval = 60) -> Bool {
    guard
        let payload = decodeJWTPayload(token),
        let exp     = payload["exp"] as? TimeInterval
    else { return true }
    return Date().timeIntervalSince1970 >= exp - buffer
}

public struct CodexAuthClaim: Equatable, Sendable {
    public let email: String?
    public let plan: String?

    public init(email: String?, plan: String?) {
        self.email = email
        self.plan = plan
    }
}

public func codexAuthClaim(from payload: [String: Any]) -> CodexAuthClaim {
    let currentAuth = payload["https://api.openai.com/auth"] as? [String: Any]
    let legacyAuth = payload["auth"] as? [String: Any]
    let auth = currentAuth ?? legacyAuth
    return CodexAuthClaim(
        email: payload["email"] as? String,
        plan: auth?["chatgpt_plan_type"] as? String
    )
}

public enum CodexWhamUsageParser {
    public static func service(from data: Data, fallbackEmail: String? = nil) -> Service? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let plan = root["plan_type"] as? String
        let email = (root["email"] as? String) ?? fallbackEmail
        var quotas: [Quota] = []

        if let rateLimit = root["rate_limit"] as? [String: Any] {
            if let primary = parseWindow(rateLimit["primary_window"]) {
                quotas.append(primary)
            }
            if let secondary = parseWindow(rateLimit["secondary_window"]) {
                quotas.append(secondary)
            }
        }

        if let credits = root["credits"] as? [String: Any],
           let hasCredits = credits["has_credits"] as? Bool,
           hasCredits,
           let balance = numericValue(credits["balance"]) {
            quotas.append(Quota(
                type: .tokens,
                total: nil,
                used: balance,
                unit: "credits",
                resetsAt: nil
            ))
        }

        guard !quotas.isEmpty || plan != nil || email != nil else { return nil }

        return Service(
            label: WidgetValueComputer.codexServiceLabel(plan: plan),
            quotas: quotas,
            currentSession: SessionSnapshot(
                id: "codex-wham-usage",
                startedAt: ISO8601DateFormatter().string(from: Date()),
                tokens: nil,
                time: nil,
                money: nil,
                requests: nil
            ),
            error: nil
        )
    }

    private static func parseWindow(_ raw: Any?) -> Quota? {
        guard let dict = raw as? [String: Any],
              let usedPercent = numericValue(dict["used_percent"]),
              let windowSeconds = numericValue(dict["limit_window_seconds"])
        else { return nil }

        let resetTimestamp = numericValue(dict["reset_at"])
        let resetsAt = resetTimestamp.map {
            ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0))
        }

        return Quota(
            type: .time,
            total: windowSeconds,
            used: windowSeconds * (usedPercent / 100),
            unit: "seconds",
            resetsAt: resetsAt
        )
    }

    private static func numericValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }
}

/// Build a `Service` representing a successful Codex data fetch.
/// Token usage is stored in `currentSession.tokens`; the cost quota uses
/// `hard_limit_usd` from the billing/subscription API as its ceiling.
public func buildCodexService(
    costUsd: Double,
    costLimitUsd: Double,
    tokensUsed: Int,
    now: Date = Date()
) -> Service {
    let calendar    = Calendar.current
    let firstOfMonth = calendar.date(
        from: calendar.dateComponents([.year, .month], from: now)
    ) ?? now
    let startedAt = ISO8601DateFormatter().string(from: firstOfMonth)

    return Service(
        label: "Codex",
        quotas: [
            Quota(type: .money, total: costLimitUsd, used: costUsd, unit: "USD", resetsAt: nil)
        ],
        currentSession: SessionSnapshot(
            id: "codex-monthly",
            startedAt: startedAt,
            tokens: Double(tokensUsed),
            time: nil,
            money: costUsd,
            requests: nil
        )
    )
}

/// Build a `Service` that carries an error description and no quota data.
public func buildCodexErrorService(error: String) -> Service {
    Service(label: "Codex", quotas: [], currentSession: nil, error: error)
}

/// Merge a Codex `Service` into an existing `StateFile`, preserving all other services.
/// If `existing` is nil (file doesn't exist yet), creates a new `StateFile`.
public func mergeCodexService(_ service: Service, into existing: StateFile?, now: Date = Date()) -> StateFile {
    var services        = existing?.services ?? [:]
    services["codex"]  = service
    return StateFile(
        version:   existing?.version ?? 1,
        updatedAt: ISO8601DateFormatter().string(from: now),
        services:  services
    )
}
