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
