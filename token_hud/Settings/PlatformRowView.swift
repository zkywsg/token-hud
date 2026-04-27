// token_hud/Settings/PlatformRowView.swift
import SwiftUI
import WebKit

// MARK: - Model

struct PlatformConfig: Identifiable {
    let id: String           // matches StateFile.services key, e.g. "claude", "openai", "codex"
    let displayName: String
    let credentialType: CredentialType

    enum CredentialType { case sessionKey, apiKey, codexLocalAuth }

    static let all: [PlatformConfig] = [
        PlatformConfig(id: "claude", displayName: "Claude", credentialType: .sessionKey),
        PlatformConfig(id: "openai", displayName: "OpenAI", credentialType: .apiKey),
        PlatformConfig(id: "codex", displayName: "Codex", credentialType: .codexLocalAuth),
        PlatformConfig(id: "gemini", displayName: "Gemini", credentialType: .apiKey),
        PlatformConfig(id: "deepseek", displayName: "DeepSeek", credentialType: .apiKey),
        PlatformConfig(id: "anthropic", displayName: "Anthropic API", credentialType: .apiKey),
        PlatformConfig(id: "minimax", displayName: "MiniMax", credentialType: .apiKey),
        PlatformConfig(id: "mimo", displayName: "MiMo", credentialType: .apiKey),
    ]
}

enum CodexAuthStatus: Equatable {
    case configured(email: String, plan: String)
    case expired
    case notConfigured
}

// MARK: - Row view

struct PlatformRowView: View {
    let platform: PlatformConfig
    @Binding var isExpanded: Bool

    @Environment(StateWatcher.self) private var stateWatcher
    @Environment(CodexFetcher.self) private var codexFetcher
    @Environment(APIPlatformFetcher.self) private var apiPlatformFetcher

    @State private var storedKey: String? = nil
    @State private var storedMiMoCookie: String? = nil
    @State private var miMoCookieInput: String = ""
    @State private var isShowingMiMoConnector = false
    @State private var miMoConnectorStatus = "打开窗口后请登录 MiMo 控制台。"

    // Claude-specific
    @State private var claudeState: ClaudeState = .idle
    @State private var selectedBrowser: BrowserType = .safari
    private let extractor = SessionKeyExtractor()

    // Codex-specific
    @State private var codexStatus: CodexAuthStatus = .notConfigured

    // MARK: - Badge helpers

    private var configBadgeColor: Color {
        switch platform.credentialType {
        case .sessionKey, .apiKey:
            if platform.id == "mimo" {
                return (storedKey != nil || storedMiMoCookie != nil) ? .green : .orange
            }
            return storedKey != nil ? .green : .orange
        case .codexLocalAuth:
            switch codexStatus {
            case .configured:    return .green
            case .expired:       return .yellow
            case .notConfigured: return .orange
            }
        }
    }

    private var configBadgeText: String {
        switch platform.credentialType {
        case .sessionKey, .apiKey:
            if platform.id == "mimo" {
                return (storedKey != nil || storedMiMoCookie != nil) ? "Configured" : "Not configured"
            }
            return storedKey != nil ? "Configured" : "Not configured"
        case .codexLocalAuth:
            switch codexStatus {
            case .configured:    return "Configured"
            case .expired:       return "Token expired"
            case .notConfigured: return "Not configured"
            }
        }
    }

    // OpenAI-specific
    @State private var openAIInput: String = ""

    enum ClaudeState: Equatable {
        case idle, extracting
        case success(BrowserType), failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            rowHeader
            if isExpanded {
                Divider()
                expandedContent
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task { await loadKey() }
        .sheet(isPresented: $isShowingMiMoConnector) {
            MiMoConsoleConnectorSheet(
                status: $miMoConnectorStatus,
                onConnected: { cookie in
                    try? KeychainHelper.saveMiMoConsoleCookie(cookie)
                    storedMiMoCookie = cookie
                    isShowingMiMoConnector = false
                    Task { await apiPlatformFetcher.fetchSingle(platform: platform.id) }
                }
            )
        }
    }

    // MARK: - Header

    private var rowHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(platform.displayName).fontWeight(.medium)
                Spacer()
                Circle()
                    .fill(configBadgeColor)
                    .frame(width: 7, height: 7)
                Text(configBadgeText)
                    .font(.caption)
                    .foregroundColor(configBadgeColor == .green ? .green : .secondary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                if platform.id == "codex" {
                    Button {
                        Task { await codexFetcher.fetch() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .disabled(codexFetcher.isFetching)
                } else if platform.credentialType == .apiKey {
                    Button {
                        Task { await apiPlatformFetcher.fetchSingle(platform: platform.id) }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .disabled(apiPlatformFetcher.isFetching)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                credentialsSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                metricsSection
                    .frame(width: 145)
            }
        }
        .padding(12)
    }

    // MARK: - Credentials

    @ViewBuilder private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch platform.credentialType {
            case .sessionKey:     claudeCredentials
            case .apiKey:         apiKeyCredentials
            case .codexLocalAuth: codexCredentials
            }
        }
    }

    @ViewBuilder private var codexCredentials: some View {
        switch codexStatus {
        case .configured(let email, let plan):
            HStack {
                Text("Email").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(email).font(.caption.monospaced()).foregroundColor(.secondary)
            }
            HStack {
                Text("Plan").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(plan.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        case .expired:
            Label("Token expired", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundColor(.yellow)
            Text("Run `codex login` in Terminal to refresh.")
                .font(.caption).foregroundColor(.secondary)
        case .notConfigured:
            Label("Not configured", systemImage: "info.circle")
                .font(.caption).foregroundColor(.secondary)
            Text("Run `codex login` in Terminal to authenticate.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder private var claudeCredentials: some View {
        if let key = storedKey {
            HStack {
                Text("Session Key").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(maskedKey(key)).font(.caption.monospaced()).foregroundColor(.secondary)
            }
        }

        HStack {
            Picker("", selection: $selectedBrowser) {
                ForEach(BrowserType.allCases) { b in Text(b.rawValue).tag(b) }
            }
            .labelsHidden()
            .frame(width: 110)
            Button(claudeState == .extracting ? "Extracting…" : "Extract") {
                extractClaudeKey()
            }
            .disabled(claudeState == .extracting)
        }

        SecureField("Or paste session key", text: Binding(
            get: { "" },
            set: { v in
                guard !v.isEmpty else { return }
                Task {
                    try? await extractor.storeInKeychain(sessionKey: v)
                    try? await extractor.writeConfigFile(sessionKey: v)
                    storedKey = v
                }
            }
        ))
        .textFieldStyle(.roundedBorder)

        switch claudeState {
        case .success(let b):
            Text("Found in \(b.rawValue)").font(.caption).foregroundColor(.green)
        case .failed(let msg):
            Text(msg).font(.caption).foregroundColor(.red)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var apiKeyCredentials: some View {
        if let key = storedKey {
            HStack {
                Text("API Key").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(maskedKey(key)).font(.caption.monospaced()).foregroundColor(.secondary)
                Button("删除") {
                    try? KeychainHelper.deleteAPIKey(for: platform.id)
                    if platform.id == "mimo" {
                        try? KeychainHelper.deleteMiMoConsoleCookie()
                        storedMiMoCookie = nil
                    }
                    storedKey = nil
                    openAIInput = ""
                }
                .font(.caption).foregroundColor(.red)
            }
        }

        HStack {
            SecureField(apiKeyPlaceholder, text: $openAIInput)
                .textFieldStyle(.roundedBorder)
            Button("Save") {
                let key = openAIInput.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return }
                Task {
                    try? KeychainHelper.saveAPIKey(key, for: platform.id)
                    storedKey = key
                    openAIInput = ""
                    await apiPlatformFetcher.fetchSingle(platform: platform.id)
                }
            }
            .disabled(openAIInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        Text(apiKeyHelpText)
            .font(.caption).foregroundColor(.secondary)

        if platform.id == "mimo" {
            Divider().padding(.vertical, 2)
            if let cookie = storedMiMoCookie {
                HStack {
                    Text("Console Cookie").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(maskedKey(cookie)).font(.caption.monospaced()).foregroundColor(.secondary)
                    Button {
                        try? KeychainHelper.deleteMiMoConsoleCookie()
                        storedMiMoCookie = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Connect Console") {
                    miMoConnectorStatus = "打开窗口后请登录 MiMo 控制台。"
                    isShowingMiMoConnector = true
                }
                .font(.caption)
                SecureField("Paste Cookie", text: $miMoCookieInput)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let cookie = miMoCookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cookie.isEmpty else { return }
                    Task {
                        try? KeychainHelper.saveMiMoConsoleCookie(cookie)
                        storedMiMoCookie = cookie
                        miMoCookieInput = ""
                        await apiPlatformFetcher.fetchSingle(platform: platform.id)
                    }
                }
                .disabled(miMoCookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Token Plan 用量需要控制台登录态 Cookie；API key 只能用于模型调用。")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var apiKeyPlaceholder: String {
        switch platform.id {
        case "openai":    return "sk-…"
        case "gemini":    return "AIza…"
        case "deepseek":  return "sk-…"
        case "anthropic": return "sk-ant-…"
        case "minimax":   return "eyJ…"
        case "mimo":      return "sk-…"
        default:          return "API key"
        }
    }

    private var apiKeyHelpText: String {
        switch platform.id {
        case "openai":    return "platform.openai.com → API keys → Create new secret key"
        case "gemini":    return "aistudio.google.com → API keys → Create API key"
        case "deepseek":  return "platform.deepseek.com → API keys → Create new secret key"
        case "anthropic": return "console.anthropic.com → API keys → Create key"
        case "minimax":   return "platform.minimax.io → API keys → Create new secret key"
        case "mimo":      return "platform.xiaomimimo.com → API keys → Create new secret key"
        default:          return "Enter your API key"
        }
    }

    // MARK: - Metrics

    @ViewBuilder private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let service = stateWatcher.currentState?.services[platform.id] {
                if let errorMsg = service.error {
                    codexErrorLabel(errorMsg)
                } else if service.quotas.isEmpty, service.currentSession == nil {
                    noQuotaDataLabel
                } else {
                    if platform.id == "codex", case .configured(_, let plan) = codexStatus {
                        HStack {
                            Text("订阅").font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text(plan.capitalized)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }
                    }
                    ForEach(Array(service.quotas.enumerated()), id: \.offset) { _, quota in
                        quotaRow(quota)
                    }
                    if let session = service.currentSession {
                        sessionSummary(session)
                    }
                }
            } else {
                Text("No data").font(.caption).foregroundColor(.secondary)
            }
            if shouldShowRefreshButton {
                Divider()
                refreshButton
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private func codexErrorLabel(_ error: String) -> some View {
        let (icon, color, message): (String, Color, String) = {
            switch error {
            case "notConfigured":
                return ("info.circle", .secondary, "Not configured")
            case "tokenExpired":
                return ("exclamationmark.triangle", .orange, "Token expired — run `codex login`")
            case "apiForbidden":
                return ("lock", .yellow, "API access denied (403)")
            case "networkError":
                return ("wifi.slash", .gray, "Network unavailable")
            default:
                if error.hasPrefix("apiError(") {
                    return ("xmark.circle", .yellow, error)
                }
                return ("xmark.circle", .secondary, error)
            }
        }()
        Label(message, systemImage: icon)
            .font(.caption)
            .foregroundColor(color)
    }

    private var noQuotaDataLabel: some View {
        Label("API 已连接，平台未提供余额/用量接口", systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundColor(.green)
    }

    @ViewBuilder private func quotaRow(_ quota: Quota) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(quotaLabel(quota)).font(.caption2).foregroundColor(.secondary)
            if quota.total != nil {
                // Has a cap: show progress bar with percentage
                HStack(spacing: 4) {
                    ProgressView(value: quota.usedFraction)
                        .progressViewStyle(.linear)
                        .tint(quota.usedFraction > 0.8 ? .red : .accentColor)
                    Text(String(format: "%.0f%%", quota.usedFraction * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            Text(quotaRemainingString(quota)).font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func maskedKey(_ key: String) -> String {
        guard key.count > 10 else { return "••••••••" }
        return String(key.prefix(6)) + "••••" + String(key.suffix(4))
    }

    private func quotaLabel(_ quota: Quota) -> String {
        if quota.unit.lowercased() == "credits" {
            return "Credits 用量"
        }
        switch quota.type {
        case .time:
            let hours = (quota.total ?? 0) / 3600
            return hours >= 24 ? "\(Int(hours / 24)) 天窗口" : "\(Int(hours)) 小时限制"
        case .money:          return "账户余额"
        case .tokens:         return "Token 用量"
        case .requests:       return "请求次数"
        case .inputTokens:    return "输入 Token"
        case .outputTokens:   return "输出 Token"
        case .dailyTokens:    return "日 Token 用量"
        case .monthlyTokens:  return "月 Token 用量"
        case .costSpent:      return "已花费"
        case .dailyRequests:  return "日请求数"
        case .monthlyRequests: return "月请求数"
        }
    }

    private func quotaRemainingString(_ quota: Quota) -> String {
        guard quota.total != nil else {
            switch quota.type {
            case .time:          return formatDuration(quota.used) + " 已用"
            case .money:         return currencyPrefix(quota.unit) + String(format: "%.2f", quota.used)
            case .tokens:        return formatTokens(quota.used) + " 已用"
            case .requests:      return "\(Int(quota.used)) 已用"
            case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens:
                return formatTokens(quota.used) + " 已用"
            case .dailyRequests, .monthlyRequests:
                return "\(Int(quota.used)) 已用"
            case .costSpent:
                return currencyPrefix(quota.unit) + String(format: "%.2f", quota.used)
            }
        }
        switch quota.type {
        case .time:          return formatDuration(quota.remaining) + " 剩余"
        case .money:         return currencyPrefix(quota.unit) + String(format: "%.2f", quota.remaining) + " 剩余"
        case .tokens:        return formatTokens(quota.remaining) + " 剩余"
        case .requests:      return "\(Int(quota.remaining)) 剩余"
        case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens:
            return formatTokens(quota.remaining) + " 剩余"
        case .dailyRequests, .monthlyRequests:
            return "\(Int(quota.remaining)) 剩余"
        case .costSpent:
            return currencyPrefix(quota.unit) + String(format: "%.2f", quota.remaining) + " 剩余"
        }
    }

    private func formatTokens(_ t: Double) -> String {
        if t >= 1_000_000 { return String(format: "%.1fM", t / 1_000_000) }
        if t >= 1_000 { return String(format: "%.0fk", t / 1_000) }
        return "\(Int(t))"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 60)m"
    }

    private func currencyPrefix(_ unit: String) -> String {
        switch unit.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        default:    return "$"
        }
    }

    @ViewBuilder private func sessionSummary(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 4) {
            Text("会话:").font(.caption2).foregroundColor(.secondary)
            if let t = session.tokens { Text(formatTokens(t) + " tokens").font(.caption2).foregroundColor(.secondary) }
            if let m = session.money { Text("· " + currencyPrefix("USD") + String(format: "%.2f", m)).font(.caption2).foregroundColor(.secondary) }
            if let r = session.requests { Text("· \(Int(r)) req").font(.caption2).foregroundColor(.secondary) }
        }
    }

    private var shouldShowRefreshButton: Bool {
        platform.credentialType == .codexLocalAuth ||
        (platform.credentialType == .apiKey && storedKey != nil)
    }

    private var isRefreshing: Bool {
        switch platform.credentialType {
        case .codexLocalAuth:
            return codexFetcher.isFetching
        case .apiKey:
            return apiPlatformFetcher.isFetching
        case .sessionKey:
            return false
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                switch platform.credentialType {
                case .codexLocalAuth:
                    await codexFetcher.fetch()
                case .apiKey:
                    await apiPlatformFetcher.fetchSingle(platform: platform.id)
                case .sessionKey:
                    break
                }
            }
        } label: {
            if isRefreshing {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Refreshing…").font(.caption2)
                }
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .disabled(isRefreshing)
    }

    private func loadKey() async {
        switch platform.credentialType {
        case .sessionKey:
            storedKey = await extractor.loadFromKeychain()
        case .apiKey:
            storedKey = KeychainHelper.loadAPIKey(for: platform.id)
            if platform.id == "mimo" {
                storedMiMoCookie = KeychainHelper.loadMiMoConsoleCookie()
            }
        case .codexLocalAuth: loadCodexStatus()
        }
    }

    private func extractClaudeKey() {
        claudeState = .extracting
        Task {
            do {
                if let (browser, key) = try await extractor.extractFromBrowser(selectedBrowser) {
                    try await extractor.storeInKeychain(sessionKey: key)
                    try await extractor.writeConfigFile(sessionKey: key)
                    storedKey = key
                    claudeState = .success(browser)
                } else {
                    claudeState = .failed("Not found in \(selectedBrowser.rawValue). Try another browser.")
                }
            } catch {
                claudeState = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor private func loadCodexStatus() {
        let authPath = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard
            let data = FileManager.default.contents(atPath: authPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String,
            let accessToken = tokens["access_token"] as? String,
            let payload = decodeCodexJwtPayload(idToken)
        else {
            codexStatus = .notConfigured
            return
        }

        // Check expiry using access_token (60s buffer).
        // If we can't decode the token or it has no exp claim, treat as expired.
        guard
            let accessPayload = decodeCodexJwtPayload(accessToken),
            let exp = accessPayload["exp"] as? TimeInterval,
            Date().timeIntervalSince1970 < exp - 60
        else {
            codexStatus = .expired
            return
        }

        let auth = payload["auth"] as? [String: Any]
        let plan = (auth?["chatgpt_plan_type"] as? String) ?? "unknown"
        let email = (payload["email"] as? String) ?? ""
        codexStatus = .configured(email: email, plan: plan)
    }

    /// Decode the payload segment of a JWT. Returns nil on any parse failure.
    private func decodeCodexJwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder > 0 { b64 += String(repeating: "=", count: 4 - remainder) }
        guard
            let data = Data(base64Encoded: b64),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }
}

// MARK: - API Key Group View

struct APIKeyGroupView: View {
    @Binding var selectedPlatform: String
    @Environment(StateWatcher.self) private var stateWatcher
    @Environment(APIPlatformFetcher.self) private var apiPlatformFetcher

    private var apiPlatforms: [PlatformConfig] {
        PlatformConfig.all.filter { $0.credentialType == .apiKey }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("API Key 平台").fontWeight(.medium)
                Spacer()
                Button {
                    Task { await apiPlatformFetcher.fetchSingle(platform: selectedPlatform) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(apiPlatformFetcher.isFetching)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 0) {
                ForEach(apiPlatforms) { platform in
                    APIPlatformRow(
                        platform: platform,
                        isSelected: selectedPlatform == platform.id
                    ) {
                        selectedPlatform = platform.id
                    }
                }

                Divider().padding(.horizontal, 12)

                if let service = stateWatcher.currentState?.services[selectedPlatform] {
                    MetricsDetailView(service: service)
                        .padding(12)
                } else {
                    VStack(spacing: 4) {
                        if KeychainHelper.loadAPIKey(for: selectedPlatform) != nil {
                            Text("API key 已配置，暂无数据")
                                .font(.caption).foregroundColor(.secondary)
                            Text("点击刷新按钮获取最新状态")
                                .font(.caption2).foregroundColor(.secondary)
                        } else {
                            Text("未配置 API key")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct APIPlatformRow: View {
    let platform: PlatformConfig
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var storedKey: String? = nil
    @State private var storedMiMoCookie: String? = nil
    @State private var isEditing = false
    @State private var keyInput: String = ""
    @State private var cookieInput: String = ""
    @State private var isShowingMiMoConnector = false
    @State private var miMoConnectorStatus = "打开窗口后请登录 MiMo 控制台。"
    @Environment(APIPlatformFetcher.self) private var apiPlatformFetcher

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isConfigured ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(platform.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if let key = storedKey {
                    Text(maskedKey(key))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                } else if !isConfigured {
                    Text("未配置")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingMiMoConnector) {
            MiMoConsoleConnectorSheet(
                status: $miMoConnectorStatus,
                onConnected: { cookie in
                    try? KeychainHelper.saveMiMoConsoleCookie(cookie)
                    storedMiMoCookie = cookie
                    isShowingMiMoConnector = false
                    Task { await apiPlatformFetcher.fetchSingle(platform: platform.id) }
                }
            )
        }
        .task {
            storedKey = KeychainHelper.loadAPIKey(for: platform.id)
            if platform.id == "mimo" {
                storedMiMoCookie = KeychainHelper.loadMiMoConsoleCookie()
            }
        }

        if isSelected {
            VStack(spacing: 6) {
                if isEditing || storedKey == nil {
                    HStack {
                        SecureField(apiKeyPlaceholder, text: $keyInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            let key = keyInput.trimmingCharacters(in: .whitespaces)
                            guard !key.isEmpty else { return }
                            try? KeychainHelper.saveAPIKey(key, for: platform.id)
                            storedKey = key
                            keyInput = ""
                            isEditing = false
                            Task { await apiPlatformFetcher.fetchSingle(platform: platform.id) }
                        }
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        if storedKey != nil {
                            Button("Cancel") { isEditing = false; keyInput = "" }
                                .font(.caption)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("更换 Key") { isEditing = true }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("删除配置") {
                            try? KeychainHelper.deleteAPIKey(for: platform.id)
                            if platform.id == "mimo" {
                                try? KeychainHelper.deleteMiMoConsoleCookie()
                                storedMiMoCookie = nil
                            }
                            storedKey = nil
                            keyInput = ""
                            isEditing = false
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }

                if platform.id == "mimo" {
                    Divider().padding(.vertical, 2)
                    if let cookie = storedMiMoCookie {
                        HStack {
                            Text("Console Cookie")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(maskedKey(cookie))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Button {
                                try? KeychainHelper.deleteMiMoConsoleCookie()
                                storedMiMoCookie = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Button("Connect Console") {
                            miMoConnectorStatus = "打开窗口后请登录 MiMo 控制台。"
                            isShowingMiMoConnector = true
                        }
                        .font(.caption)
                        SecureField("Paste Cookie", text: $cookieInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            let cookie = cookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cookie.isEmpty else { return }
                            try? KeychainHelper.saveMiMoConsoleCookie(cookie)
                            storedMiMoCookie = cookie
                            cookieInput = ""
                            Task { await apiPlatformFetcher.fetchSingle(platform: platform.id) }
                        }
                        .disabled(cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Token Plan 用量需要控制台登录态 Cookie；API key 只能用于模型调用。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var isConfigured: Bool {
        storedKey != nil || (platform.id == "mimo" && storedMiMoCookie != nil)
    }

    private var apiKeyPlaceholder: String {
        switch platform.id {
        case "openai":    return "sk-…"
        case "gemini":    return "AIza…"
        case "deepseek":  return "sk-…"
        case "anthropic": return "sk-ant-…"
        case "minimax":   return "eyJ…"
        case "mimo":      return "sk-…"
        default:          return "API key"
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 10 else { return "••••••••" }
        return String(key.prefix(6)) + "••••" + String(key.suffix(4))
    }
}

private struct MiMoConsoleConnectorSheet: View {
    @Binding var status: String
    let onConnected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("连接 MiMo 控制台")
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            MiMoConsoleConnectorView(status: $status, onConnected: onConnected)
                .frame(width: 980, height: 680)
        }
        .padding(14)
        .frame(width: 1008, height: 730)
    }
}

private struct MiMoConsoleConnectorView: NSViewRepresentable {
    @Binding var status: String
    let onConnected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(status: $status, onConnected: onConnected)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let url = URL(string: "https://platform.xiaomimimo.com/console/plan-manage") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var status: String
        private let onConnected: (String) -> Void
        weak var webView: WKWebView?
        private var didConnect = false
        private var isChecking = false
        private nonisolated(unsafe) var pollTimer: Timer?

        init(status: Binding<String>, onConnected: @escaping (String) -> Void) {
            self._status = status
            self.onConnected = onConnected
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkConnection()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            status = "页面加载失败：\(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            status = "页面加载失败：\(error.localizedDescription)"
        }

        func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
        }

        deinit {
            let timer = pollTimer
            Task { @MainActor in timer?.invalidate() }
        }

        private func startPolling() {
            guard pollTimer == nil else { return }
            pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.checkConnection() }
            }
        }

        private func checkConnection() {
            guard !didConnect, !isChecking, let webView else { return }
            isChecking = true
            status = "正在检测 MiMo 登录状态..."

            let script = """
            fetch('/api/v1/tokenPlan/usage', { credentials: 'include' })
              .then(response => response.text())
              .catch(error => JSON.stringify({ code: -1, message: String(error) }))
            """

            webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
                guard let self else { return }
                self.isChecking = false

                if let error {
                    self.status = "检测失败：\(error.localizedDescription)"
                    self.startPolling()
                    return
                }

                guard
                    let text = result as? String,
                    let data = text.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    (json["code"] as? Int) == 0
                else {
                    self.status = "请登录 MiMo 控制台，登录后自动获取。"
                    self.startPolling()
                    return
                }

                self.status = "登录已确认，正在保存 Cookie..."
                DispatchQueue.main.async { self.stopPolling() }

                webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self else { return }
                    let cookieHeader = cookies
                        .filter { $0.domain.contains("xiaomimimo.com") }
                        .map { "\($0.name)=\($0.value)" }
                        .joined(separator: "; ")

                    guard !cookieHeader.isEmpty else {
                        self.status = "未找到 MiMo Cookie，请刷新页面后重试。"
                        self.startPolling()
                        return
                    }

                    self.didConnect = true
                    self.status = "已连接 MiMo 控制台。"
                    self.onConnected(cookieHeader)
                }
            }
        }
    }
}

private struct MetricsDetailView: View {
    let service: Service

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = service.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.yellow)
            } else if service.quotas.isEmpty, service.currentSession == nil {
                Label("API 已连接，平台未提供余额/用量接口", systemImage: "checkmark.circle")
                    .font(.caption).foregroundColor(.green)
            } else {
                ForEach(Array(service.quotas.enumerated()), id: \.offset) { _, quota in
                    quotaRow(quota)
                }
                if let session = service.currentSession {
                    sessionSummary(session)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func quotaRow(_ quota: Quota) -> some View {
        HStack(spacing: 6) {
            Text(quotaLabel(quota))
                .font(.caption2).foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            if quota.total != nil {
                ProgressView(value: quota.usedFraction)
                    .progressViewStyle(.linear)
                    .tint(quota.usedFraction > 0.8 ? .red : quota.usedFraction > 0.5 ? .yellow : .accentColor)
                Text(String(format: "%.0f%%", quota.usedFraction * 100))
                    .font(.caption2).foregroundColor(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
            Text(quotaRemainingString(quota))
                .font(.caption2).foregroundColor(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func sessionSummary(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 4) {
            Text("会话:").font(.caption2).foregroundColor(.secondary)
            if let t = session.tokens { Text(formatTokens(t) + " tokens").font(.caption2).foregroundColor(.secondary) }
            if let m = session.money { Text("· " + currencyPrefix("USD") + String(format: "%.2f", m)).font(.caption2).foregroundColor(.secondary) }
            if let r = session.requests { Text("· \(Int(r)) req").font(.caption2).foregroundColor(.secondary) }
        }
    }

    private func quotaLabel(_ quota: Quota) -> String {
        if quota.unit.lowercased() == "credits" { return "Credits 用量" }
        switch quota.type {
        case .time: let hours = (quota.total ?? 0) / 3600; return hours >= 24 ? "\(Int(hours/24)) 天窗口" : "\(Int(hours)) 小时限制"
        case .money: return "账户余额"; case .tokens: return "Token 用量"; case .requests: return "请求次数"
        case .inputTokens: return "输入 Token"; case .outputTokens: return "输出 Token"
        case .dailyTokens: return "日 Token 用量"; case .monthlyTokens: return "月 Token 用量"
        case .costSpent: return "已花费"; case .dailyRequests: return "日请求数"; case .monthlyRequests: return "月请求数"
        }
    }

    private func quotaRemainingString(_ quota: Quota) -> String {
        guard quota.total != nil else {
            switch quota.type {
            case .time: return formatDuration(quota.used) + " 已用"
            case .money: return currencyPrefix(quota.unit) + String(format: "%.2f", quota.used)
            case .tokens: return formatTokens(quota.used) + " 已用"
            case .requests: return "\(Int(quota.used)) 已用"
            case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens: return formatTokens(quota.used) + " 已用"
            case .dailyRequests, .monthlyRequests: return "\(Int(quota.used)) 已用"
            case .costSpent: return currencyPrefix(quota.unit) + String(format: "%.2f", quota.used)
            }
        }
        switch quota.type {
        case .time: return formatDuration(quota.remaining) + " 剩余"
        case .money: return currencyPrefix(quota.unit) + String(format: "%.2f", quota.remaining) + " 剩余"
        case .tokens: return formatTokens(quota.remaining) + " 剩余"
        case .requests: return "\(Int(quota.remaining)) 剩余"
        case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens: return formatTokens(quota.remaining) + " 剩余"
        case .dailyRequests, .monthlyRequests: return "\(Int(quota.remaining)) 剩余"
        case .costSpent: return currencyPrefix(quota.unit) + String(format: "%.2f", quota.remaining) + " 剩余"
        }
    }

    private func formatTokens(_ t: Double) -> String {
        if t >= 1_000_000 { return String(format: "%.1fM", t/1_000_000) }
        if t >= 1_000 { return String(format: "%.0fk", t/1_000) }
        return "\(Int(t))"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return "\(s/3600)h \((s%3600)/60)m" }
        return "\(s/60)m"
    }

    private func currencyPrefix(_ unit: String) -> String {
        switch unit.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        default:    return "$"
        }
    }
}
