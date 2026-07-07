import SwiftUI

// MARK: - Shared UI components for Platform settings

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct StoredSecretRow: View {
    let label: String
    let maskedValue: String?

    var body: some View {
        InfoRow(label: label, value: maskedValue ?? "未配置")
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                labelText
                Spacer(minLength: 12)
                valueText
                    .frame(maxWidth: 280, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 3) {
                labelText
                valueText
            }
        }
    }

    private var labelText: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var valueText: some View {
        Text(value)
            .font(.caption.monospaced())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.82)
    }
}

struct QuotaStatusRow: View {
    let quota: Quota

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quotaTitle)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(quotaValue)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
            if quota.total != nil {
                ProgressView(value: min(max(quota.usedFraction, 0), 1))
                    .tint(quota.usedFraction > 0.85 ? .red : .accentColor)
            }
        }
    }

    private var quotaTitle: String {
        switch quota.type {
        case .time:            return "时间窗口"
        case .tokens:          return "Token"
        case .money:           return "余额"
        case .requests:        return "请求"
        case .inputTokens:     return "输入 Token"
        case .outputTokens:    return "输出 Token"
        case .dailyTokens:     return "日 Token"
        case .monthlyTokens:   return "月 Token"
        case .dailyRequests:   return "日请求"
        case .monthlyRequests: return "月请求"
        case .costSpent:       return "已花费"
        }
    }

    private var quotaValue: String {
        if let total = quota.total {
            return "\(format(quota.used)) / \(format(total)) \(quota.unit)"
        }
        return "\(format(quota.used)) \(quota.unit)"
    }

    private func format(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", value / 1_000) }
        if value == floor(value) { return "\(Int(value))" }
        return String(format: "%.2f", value)
    }
}

struct SessionStatusRow: View {
    let session: SessionSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text(sessionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var sessionText: String {
        var parts: [String] = []
        if let tokens = session.tokens { parts.append("\(compact(tokens)) tokens") }
        if let requests = session.requests { parts.append("\(Int(requests)) req") }
        if let cost = session.costSpent { parts.append("$" + String(format: "%.2f", cost)) }
        return parts.isEmpty ? "暂无会话摘要" : parts.joined(separator: " · ")
    }

    private func compact(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", value / 1_000) }
        return "\(Int(value))"
    }
}

func sectionHeader(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
}

// MARK: - Provider extensions

extension ProviderCapability {
    var canRefresh: Bool {
        credentialKind == .codexLocalAuth ||
        credentialKind == .apiKey ||
        credentialKind == .apiKeyAndConsoleCookie ||
        credentialKind == .sessionKey
    }
}

extension ProviderCredentialKind {
    var displayTitle: String {
        switch self {
        case .sessionKey:             return "Session Key"
        case .apiKey:                 return "API Key"
        case .codexLocalAuth:         return "Codex 本地认证"
        case .apiKeyAndConsoleCookie: return "API Key + Console Cookie"
        }
    }
}

extension ProviderUsageCapability {
    var displayTitle: String {
        switch self {
        case .localSessionLogs:       return "本地日志"
        case .balanceEndpoint:        return "官方余额接口"
        case .tokenPlanEndpoint:      return "Token Plan 接口"
        case .consoleCookieTokenPlan: return "控制台 Token Plan"
        case .apiKeyValidationOnly:   return "仅验证 Key"
        }
    }

    var detail: String {
        switch self {
        case .localSessionLogs:
            return "从本机 session 日志读取用量，不发起平台账单请求。"
        case .balanceEndpoint:
            return "平台提供可直接查询余额或额度的官方接口。"
        case .tokenPlanEndpoint:
            return "平台提供 Token Plan remains / usage 类接口，适合展示套餐剩余额度。"
        case .consoleCookieTokenPlan:
            return "普通 API key 只验证调用能力；Token Plan 需要控制台登录态 Cookie。"
        case .apiKeyValidationOnly:
            return "普通 API key 不保证能读取账单或组织用量；Settings 会明确显示不支持，而不是伪造额度。"
        }
    }
}

extension ProviderDataStatus {
    var title: String {
        title(for: nil)
    }

    func title(for providerID: String?) -> String {
        if self == .usageUnsupported, providerID == "minimax" {
            return "无套餐数据"
        }
        switch self {
        case .notQueried:       return "未查询"
        case .noUsageData:      return "暂无数据"
        case .usageUnsupported: return "用量不支持"
        case .tokenExpired:     return "Token 过期"
        case .permissionDenied: return "权限不足"
        case .networkError:     return "网络错误"
        case .error:            return "查询异常"
        case .ready:            return "有数据"
        }
    }

    var detail: String {
        detail(for: nil)
    }

    func detail(for providerID: String?) -> String {
        switch self {
        case .notQueried:
            return "还没有当前平台的数据。配置认证后点击刷新，或等待自动刷新。"
        case .noUsageData:
            return "已配置或已连接，但当前平台暂无可展示的用量数据。"
        case .usageUnsupported:
            if providerID == "minimax" {
                return "MiniMax 普通 Open Platform API Key 可验证调用，但公开接口不能查询余额/套餐；只有 Token Plan remains 返回 quota 时才会展示用量。"
            }
            return "普通 API key 暂不支持直接读取用量或账单，需要额外组织/账单权限或外部数据源。"
        case .tokenExpired:
            return "认证已过期，需要重新登录或重新配置凭据。"
        case .permissionDenied:
            return "当前凭据没有查询该数据的权限。"
        case .networkError:
            return "网络请求失败，稍后重试或检查代理/网络。"
        case .error:
            return "查询结果无法解析或平台返回异常。"
        case .ready:
            return "当前平台已有可展示数据。"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:            return "checkmark.circle"
        case .usageUnsupported: return "info.circle"
        case .tokenExpired:     return "exclamationmark.triangle"
        case .permissionDenied: return "lock"
        case .networkError:     return "wifi.slash"
        case .error:            return "xmark.circle"
        case .notQueried, .noUsageData:
            return "tray"
        }
    }

    var color: Color {
        switch self {
        case .ready:            return .green
        case .usageUnsupported: return .blue
        case .tokenExpired:     return .orange
        case .permissionDenied: return .yellow
        case .networkError:     return .secondary
        case .error:            return .red
        case .notQueried, .noUsageData:
            return .secondary
        }
    }
}
