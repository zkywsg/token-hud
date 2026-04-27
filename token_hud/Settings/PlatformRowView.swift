// token_hud/Settings/PlatformRowView.swift
import SwiftUI

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

    @State private var storedKey: String? = nil

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
        HStack(alignment: .top, spacing: 12) {
            credentialsSection
                .frame(maxWidth: .infinity, alignment: .leading)
            metricsSection
                .frame(width: 145)
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
                }
            }
            .disabled(openAIInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        Text(apiKeyHelpText)
            .font(.caption).foregroundColor(.secondary)
    }

    private var apiKeyPlaceholder: String {
        switch platform.id {
        case "openai":    return "sk-…"
        case "gemini":    return "AIza…"
        case "deepseek":  return "sk-…"
        case "anthropic": return "sk-ant-…"
        default:          return "API key"
        }
    }

    private var apiKeyHelpText: String {
        switch platform.id {
        case "openai":    return "platform.openai.com → API keys → Create new secret key"
        case "gemini":    return "aistudio.google.com → API keys → Create API key"
        case "deepseek":  return "platform.deepseek.com → API keys → Create new secret key"
        case "anthropic": return "console.anthropic.com → API keys → Create key"
        default:          return "Enter your API key"
        }
    }

    // MARK: - Metrics

    @ViewBuilder private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let service = stateWatcher.currentState?.services[platform.id] {
                if let errorMsg = service.error {
                    codexErrorLabel(errorMsg)
                } else {
                    ForEach(Array(service.quotas.enumerated()), id: \.offset) { _, quota in
                        quotaRow(quota)
                    }
                }
            } else {
                Text("No data").font(.caption).foregroundColor(.secondary)
            }
            if platform.credentialType == .codexLocalAuth {
                Divider()
                Button {
                    Task { await codexFetcher.fetch() }
                } label: {
                    if codexFetcher.isFetching {
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
                .disabled(codexFetcher.isFetching)
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
        switch quota.type {
        case .time:
            let hours = (quota.total ?? 0) / 3600
            return hours >= 24 ? "\(Int(hours / 24))d window" : "\(Int(hours))h window"
        case .money:          return "Balance"
        case .tokens:         return "Tokens"
        case .requests:       return "Requests"
        case .inputTokens:    return "Input Tokens"
        case .outputTokens:   return "Output Tokens"
        case .dailyTokens:    return "Daily Tokens"
        case .monthlyTokens:  return "Monthly Tokens"
        case .costSpent:      return "Cost Spent"
        case .dailyRequests:  return "Daily Requests"
        case .monthlyRequests: return "Monthly Requests"
        }
    }

    private func quotaRemainingString(_ quota: Quota) -> String {
        // For no-cap quotas, show usage instead of remaining
        guard quota.total != nil else {
            switch quota.type {
            case .time:          return formatDuration(quota.used) + " used"
            case .money:         return String(format: "$%.2f used", quota.used)
            case .tokens:        return formatTokens(quota.used) + " used"
            case .requests:      return "\(Int(quota.used)) used"
            case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens:
                return formatTokens(quota.used) + " used"
            case .dailyRequests, .monthlyRequests:
                return "\(Int(quota.used)) used"
            case .costSpent:
                return String(format: "$%.2f used", quota.used)
            }
        }
        switch quota.type {
        case .time:          return formatDuration(quota.remaining) + " left"
        case .money:         return String(format: "$%.2f left", quota.remaining)
        case .tokens:        return formatTokens(quota.remaining) + " left"
        case .requests:      return "\(Int(quota.remaining)) left"
        case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens:
            return formatTokens(quota.remaining) + " left"
        case .dailyRequests, .monthlyRequests:
            return "\(Int(quota.remaining)) left"
        case .costSpent:
            return String(format: "$%.2f left", quota.remaining)
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

    private func loadKey() async {
        switch platform.credentialType {
        case .sessionKey:     storedKey = await extractor.loadFromKeychain()
        case .apiKey:         storedKey = KeychainHelper.loadAPIKey(for: platform.id)
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

    private var apiPlatforms: [PlatformConfig] {
        PlatformConfig.all.filter { $0.credentialType == .apiKey }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("API Key 平台").fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    Text("No data")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    @State private var isEditing = false
    @State private var keyInput: String = ""

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(storedKey != nil ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(platform.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if let key = storedKey {
                    Text(maskedKey(key))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
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
        .task { storedKey = KeychainHelper.loadAPIKey(for: platform.id) }

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
                        }
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        if storedKey != nil {
                            Button("Cancel") { isEditing = false; keyInput = "" }
                                .font(.caption)
                        }
                    }
                } else {
                    Button("更换 Key") { isEditing = true }
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var apiKeyPlaceholder: String {
        switch platform.id {
        case "openai":    return "sk-…"
        case "gemini":    return "AIza…"
        case "deepseek":  return "sk-…"
        case "anthropic": return "sk-ant-…"
        default:          return "API key"
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 10 else { return "••••••••" }
        return String(key.prefix(6)) + "••••" + String(key.suffix(4))
    }
}

private struct MetricsDetailView: View {
    let service: Service

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = service.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.yellow)
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
            if let m = session.money { Text(String(format: "· $%.2f", m)).font(.caption2).foregroundColor(.secondary) }
            if let r = session.requests { Text("· \(Int(r)) req").font(.caption2).foregroundColor(.secondary) }
        }
    }

    private func quotaLabel(_ quota: Quota) -> String {
        switch quota.type {
        case .time: let hours = (quota.total ?? 0) / 3600; return hours >= 24 ? "\(Int(hours/24))d window" : "\(Int(hours))h window"
        case .money: return "Balance"; case .tokens: return "Tokens"; case .requests: return "Requests"
        case .inputTokens: return "Input Tokens"; case .outputTokens: return "Output Tokens"
        case .dailyTokens: return "Daily Tokens"; case .monthlyTokens: return "Monthly Tokens"
        case .costSpent: return "Cost Spent"; case .dailyRequests: return "Daily Requests"; case .monthlyRequests: return "Monthly Requests"
        }
    }

    private func quotaRemainingString(_ quota: Quota) -> String {
        guard quota.total != nil else {
            switch quota.type {
            case .time: return formatDuration(quota.used) + " used"
            case .money: return String(format: "$%.2f used", quota.used)
            case .tokens: return formatTokens(quota.used) + " used"
            case .requests: return "\(Int(quota.used)) used"
            case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens: return formatTokens(quota.used) + " used"
            case .dailyRequests, .monthlyRequests: return "\(Int(quota.used)) used"
            case .costSpent: return String(format: "$%.2f used", quota.used)
            }
        }
        switch quota.type {
        case .time: return formatDuration(quota.remaining) + " left"
        case .money: return String(format: "$%.2f left", quota.remaining)
        case .tokens: return formatTokens(quota.remaining) + " left"
        case .requests: return "\(Int(quota.remaining)) left"
        case .inputTokens, .outputTokens, .dailyTokens, .monthlyTokens: return formatTokens(quota.remaining) + " left"
        case .dailyRequests, .monthlyRequests: return "\(Int(quota.remaining)) left"
        case .costSpent: return String(format: "$%.2f left", quota.remaining)
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
}
