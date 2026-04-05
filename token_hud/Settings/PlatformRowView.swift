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
            case .apiKey:         openAICredentials
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

    @ViewBuilder private var openAICredentials: some View {
        if let key = storedKey {
            HStack {
                Text("API Key").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(maskedKey(key)).font(.caption.monospaced()).foregroundColor(.secondary)
            }
        }

        HStack {
            SecureField("sk-…", text: $openAIInput)
                .textFieldStyle(.roundedBorder)
            Button("Save") {
                let key = openAIInput.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return }
                Task {
                    try? KeychainHelper.saveOpenAIKey(key)
                    storedKey = key
                    openAIInput = ""
                }
            }
            .disabled(openAIInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        Text("platform.openai.com → API keys → Create new secret key")
            .font(.caption).foregroundColor(.secondary)
    }

    // MARK: - Metrics

    @ViewBuilder private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let service = stateWatcher.currentState?.services[platform.id] {
                ForEach(service.quotas, id: \.type.rawValue) { quota in
                    quotaRow(quota)
                }
            } else {
                Text("No data").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private func quotaRow(_ quota: Quota) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(quotaLabel(quota)).font(.caption2).foregroundColor(.secondary)
            ProgressView(value: quota.usedFraction)
                .progressViewStyle(.linear)
                .tint(quota.usedFraction > 0.8 ? .red : .accentColor)
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
            let hours = quota.total / 3600
            return hours >= 24 ? "\(Int(hours / 24))d window" : "\(Int(hours))h window"
        case .money:    return "Balance"
        case .tokens:   return "Tokens"
        case .requests: return "Requests"
        }
    }

    private func quotaRemainingString(_ quota: Quota) -> String {
        switch quota.type {
        case .time:     return formatDuration(quota.remaining) + " left"
        case .money:    return String(format: "$%.2f left", quota.remaining)
        case .tokens:   return "\(Int(quota.remaining / 1000))k left"
        case .requests: return "\(Int(quota.remaining)) left"
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 60)m"
    }

    private func loadKey() async {
        switch platform.credentialType {
        case .sessionKey:     storedKey = await extractor.loadFromKeychain()
        case .apiKey:         storedKey = KeychainHelper.loadOpenAIKey()
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
