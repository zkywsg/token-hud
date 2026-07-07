import SwiftUI

struct PlatformListView: View {
    @Environment(StateWatcher.self) private var stateWatcher
    @Environment(CodexFetcher.self) private var codexFetcher
    @Environment(APIPlatformFetcher.self) private var apiPlatformFetcher

    @State private var selectedPlatformID = "codex"
    @State private var revision = 0
    @State private var resetMessage: String?
    @State private var resetMessageGate = NotchTransitionGate()
    @State private var refreshingPlatformIDs = Set<String>()
    @State private var credentialSnapshot = ProviderCredentialSnapshot.empty
    @State private var authorizationNeededPlatformIDs = Set<String>()

    private var selectedProvider: ProviderCapability {
        ProviderCapability.catalog[selectedPlatformID] ?? ProviderCapability.all[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            platformSidebar
                .frame(width: 260)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.8)
            PlatformDetailView(
                provider: selectedProvider,
                service: stateWatcher.currentState?.services[selectedProvider.id],
                revision: revision,
                credentialSnapshot: credentialSnapshot,
                needsAuthorization: authorizationNeededPlatformIDs.contains(selectedProvider.id),
                isRefreshInFlight: refreshingPlatformIDs.contains(selectedProvider.id),
                onCredentialChanged: {
                    reloadCredentialSnapshot()
                    authorizationNeededPlatformIDs.remove(selectedProvider.id)
                    showResetMessage("已保存认证；刷新会先静默查询。")
                },
                onClearData: {
                    clearData(for: selectedProvider.id)
                },
                onRefresh: {
                    refresh(provider: selectedProvider, allowUserInteraction: false)
                },
                onAuthorizeRefresh: {
                    refresh(provider: selectedProvider, allowUserInteraction: true)
                }
            )
            .environment(stateWatcher)
            .environment(codexFetcher)
            .environment(apiPlatformFetcher)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            if let resetMessage {
                Text(resetMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: CompactBlackTheme.cornerRadius))
                    .padding(.bottom, 12)
            }
        }
        .task {
            reloadCredentialSnapshot()
        }
    }

    private var platformSidebar: some View {
        let configuredCount = ProviderCapability.all.filter {
            CredentialStatusReader.status(for: $0, snapshot: credentialSnapshot) == .configured
        }.count
        let providers = ProviderCapability.all.sorted { lhs, rhs in
            let lhsConfigured = CredentialStatusReader.status(for: lhs, snapshot: credentialSnapshot) == .configured
            let rhsConfigured = CredentialStatusReader.status(for: rhs, snapshot: credentialSnapshot) == .configured
            if lhsConfigured != rhsConfigured { return lhsConfigured && !rhsConfigured }
            let lhsIndex = ProviderCapability.all.firstIndex { $0.id == lhs.id } ?? 0
            let rhsIndex = ProviderCapability.all.firstIndex { $0.id == rhs.id } ?? 0
            return lhsIndex < rhsIndex
        }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("平台")
                        .font(.headline)
                    Spacer()
                    Text("已配置 \(configuredCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.13))
                        .clipShape(Capsule())
                }
                Text("已配置平台会排在前面。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(providers) { provider in
                        PlatformSidebarRow(
                            provider: provider,
                            service: stateWatcher.currentState?.services[provider.id],
                            credentialStatus: CredentialStatusReader.status(
                                for: provider,
                                snapshot: credentialSnapshot
                            ),
                            needsAuthorization: authorizationNeededPlatformIDs.contains(provider.id),
                            isSelected: provider.id == selectedPlatformID
                        ) {
                            selectedPlatformID = provider.id
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
        .background(.ultraThinMaterial)
        .overlay {
            CompactBlackTheme.subtleFill
                .allowsHitTesting(false)
        }
    }

    private func refresh(provider: ProviderCapability, allowUserInteraction: Bool) {
        guard provider.canRefresh else { return }
        guard !refreshingPlatformIDs.contains(provider.id) else { return }

        refreshingPlatformIDs.insert(provider.id)
        let platformID = provider.id
        Task { @MainActor in
            defer {
                refreshingPlatformIDs.remove(platformID)
                stateWatcher.readNow()
            }
            switch provider.credentialKind {
            case .codexLocalAuth:
                await codexFetcher.fetch(allowUserInteraction: allowUserInteraction)
                authorizationNeededPlatformIDs.remove(provider.id)
                showResetMessage("已刷新 \(provider.displayName)")
            case .apiKey, .apiKeyAndConsoleCookie:
                let result = await apiPlatformFetcher.fetchSingle(
                    platform: provider.id,
                    allowUserInteraction: allowUserInteraction
                )
                handleRefreshResult(result, provider: provider)
            case .sessionKey:
                // Claude: scan local JSONL files
                let result = await apiPlatformFetcher.fetchSingle(
                    platform: provider.id,
                    allowUserInteraction: false
                )
                handleRefreshResult(result, provider: provider)
            }
        }
    }

    private func handleRefreshResult(
        _ result: APIPlatformFetcher.SingleFetchResult,
        provider: ProviderCapability
    ) {
        switch result {
        case .updated:
            authorizationNeededPlatformIDs.remove(provider.id)
            showResetMessage("已刷新 \(provider.displayName)")
        case .needsAuthorization:
            authorizationNeededPlatformIDs.insert(provider.id)
            showResetMessage("\(provider.displayName) 需要授权刷新")
        case .noCredential:
            authorizationNeededPlatformIDs.remove(provider.id)
            showResetMessage("\(provider.displayName) 未配置认证")
        case .noData:
            showResetMessage("\(provider.displayName) 暂无可更新数据")
        }
    }

    private func reloadCredentialSnapshot() {
        // 迁移：旧 mimoAPIKey 中的 tp- key → mimoTokenPlanKey
        if !KeychainHelper.hasMiMoTokenPlanKey(),
           let existingKey = KeychainHelper.loadAPIKey(for: "mimo"),
           existingKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("tp-") {
            try? KeychainHelper.saveMiMoTokenPlanKey(existingKey)
            try? KeychainHelper.deleteAPIKey(for: "mimo")
            MiMoAPIKeyRoleStore.clear()
        }

        var apiKeys: [String: String] = [:]
        for provider in ProviderCapability.all {
            switch provider.credentialKind {
            case .apiKey, .apiKeyAndConsoleCookie:
                if KeychainHelper.hasAPIKey(for: provider.id) {
                    apiKeys[provider.id] = provider.id == "mimo"
                        ? MiMoAPIKeyRoleStore.snapshotValue()
                        : "saved"
                }
            case .sessionKey, .codexLocalAuth:
                break
            }
        }
        credentialSnapshot = ProviderCredentialSnapshot(
            claudeSessionKey: KeychainHelper.hasClaudeSessionKey() ? "saved" : nil,
            apiKeys: apiKeys,
            mimoConsoleCookie: KeychainHelper.hasMiMoConsoleCookie() ? "saved" : nil,
            codexAdminKey: KeychainHelper.hasCodexAdminKey() ? "saved" : nil,
            mimoTokenPlanKey: KeychainHelper.hasMiMoTokenPlanKey() ? "saved" : nil,
            openaiAdminKey: KeychainHelper.hasOpenAIAdminKey() ? "saved" : nil
        )
        revision += 1
    }

    private func clearData(for platformID: String) {
        do {
            try StateServiceResetter.clearService(platformID)
            stateWatcher.readNow()
            showResetMessage("已清空 \(ProviderCapability.catalog[platformID]?.displayName ?? platformID) 数据")
        } catch {
            showResetMessage(error.localizedDescription)
        }
    }

    private func showResetMessage(_ message: String, duration: TimeInterval = 2.5) {
        resetMessage = message
        let token = resetMessageGate.advance()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if resetMessageGate.isCurrent(token) {
                resetMessage = nil
            }
        }
    }
}

enum MiMoAPIKeyRoleStore {
    private static let defaultsKey = "mimoAPIKeyRole"

    static func saveRole(for key: String) {
        let role = role(for: key)
        UserDefaults.standard.set(role.rawValue, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    static func snapshotValue() -> String {
        switch UserDefaults.standard.string(forKey: defaultsKey).flatMap(MiMoAPIKeyRole.init(rawValue:)) {
        case .tokenPlanKey:
            return "tp-saved"
        case .payAsYouGoAPIKey:
            return "sk-saved"
        case .unknownAPIKey, nil:
            return "saved"
        }
    }

    private static func role(for key: String) -> MiMoAPIKeyRole {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("tp-") { return .tokenPlanKey }
        if normalized.hasPrefix("sk-") { return .payAsYouGoAPIKey }
        return .unknownAPIKey
    }
}

private struct PlatformSidebarRow: View {
    let provider: ProviderCapability
    let service: Service?
    let credentialStatus: ProviderCredentialStatus
    let needsAuthorization: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(ProviderStatusMonitor.self) private var statusMonitor

    private var dataStatus: ProviderDataStatus {
        ProviderDataStatus.status(for: service)
    }

    private var serviceStatus: ProviderStatusMonitor.Status {
        statusMonitor.status(for: provider.id)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 3, height: 18)
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    Text(provider.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    StatusDot(color: statusDotColor)
                }
                StatusPill(
                    title: needsAuthorization ? "需授权" : dataStatus.title(for: provider.id),
                    color: needsAuthorization ? .orange : dataStatus.color
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : CompactBlackTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: CompactBlackTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CompactBlackTheme.cornerRadius)
                    .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.06), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusDotColor: Color {
        // If credential is not configured, show credential status color
        guard credentialStatus == .configured else { return credentialStatus.color }
        // Otherwise show service status
        switch serviceStatus {
        case .operational: return .green
        case .degraded:    return .yellow
        case .down:        return .red
        case .unknown:     return credentialStatus.color
        }
    }

    private var iconName: String {
        switch provider.id {
        case "claude", "anthropic": return "sparkles"
        case "codex":               return "terminal"
        case "openai":              return "circle.hexagongrid"
        case "gemini":              return "diamond"
        case "deepseek":            return "drop"
        case "minimax":             return "waveform"
        case "mimo":                return "m.circle"
        case "moonshot":            return "moon.stars"
        case "openrouter":          return "arrow.triangle.branch"
        case "qwen":                return "cloud"
        default:                    return "cpu"
        }
    }
}

private struct PlatformDetailView: View {
    let provider: ProviderCapability
    let service: Service?
    let revision: Int
    let credentialSnapshot: ProviderCredentialSnapshot
    let needsAuthorization: Bool
    let isRefreshInFlight: Bool
    let onCredentialChanged: () -> Void
    let onClearData: () -> Void
    let onRefresh: () -> Void
    let onAuthorizeRefresh: () -> Void

    @Environment(CodexFetcher.self) private var codexFetcher
    @Environment(APIPlatformFetcher.self) private var apiPlatformFetcher

    private var credentialStatus: ProviderCredentialStatus {
        CredentialStatusReader.status(for: provider, snapshot: credentialSnapshot)
    }

    private var dataStatus: ProviderDataStatus {
        ProviderDataStatus.status(for: service)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                PlatformCredentialPanel(
                    provider: provider,
                    revision: revision,
                    credentialSnapshot: credentialSnapshot,
                    onChanged: onCredentialChanged
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                PlatformCapabilityPanel(provider: provider)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                PlatformMetricsPanel(provider: provider, service: service, dataStatus: dataStatus)
                PlatformResetPanel(
                    provider: provider,
                    credentialStatus: credentialStatus,
                    onCredentialChanged: onCredentialChanged,
                    onClearData: onClearData
                )
            }
            .padding(18)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                headerTitle
                Spacer(minLength: 12)
                headerActions
            }
            VStack(alignment: .leading, spacing: 10) {
                headerTitle
                headerActions
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    statusPills
                }
                VStack(alignment: .leading, spacing: 6) {
                    statusPills
                }
            }
        }
    }

    @ViewBuilder
    private var statusPills: some View {
        StatusPill(title: credentialStatus.title, color: credentialStatus.color)
        StatusPill(title: dataStatus.title(for: provider.id), color: dataStatus.color)
        if needsAuthorization {
            StatusPill(title: "需授权刷新", color: .orange)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            if needsAuthorization {
                Button {
                    onAuthorizeRefresh()
                } label: {
                    Label("授权", systemImage: "key")
                }
                .disabled(isRefreshing || !provider.canRefresh)
                .help("允许 macOS 弹出 Keychain 授权窗口，并只刷新当前平台")
            }
            Button {
                onRefresh()
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing || !provider.canRefresh)
            .help(provider.canRefresh ? "刷新当前平台状态" : "该平台没有可直接刷新的用量接口")
        }
    }

    private var isRefreshing: Bool {
        if isRefreshInFlight { return true }
        switch provider.credentialKind {
        case .codexLocalAuth: return codexFetcher.isFetching
        case .apiKey, .apiKeyAndConsoleCookie: return apiPlatformFetcher.isFetching
        case .sessionKey: return false
        }
    }
}

private struct PlatformCredentialPanel: View {
    let provider: ProviderCapability
    let revision: Int
    let credentialSnapshot: ProviderCredentialSnapshot
    let onChanged: () -> Void

    @State private var apiKeyInput = ""
    @State private var tokenPlanKeyInput = ""
    @State private var cookieInput = ""
    @State private var codexAdminKeyInput = ""
    @State private var claudeInput = ""
    @State private var selectedBrowser: BrowserType = .safari
    @State private var extractionStatus: String?
    @State private var isExtracting = false
    @State private var codexActionStatus: String?
    @State private var isShowingMiMoConnector = false
    @State private var miMoConnectorStatus = "打开窗口后请登录 MiMo 控制台。"

    private let extractor = SessionKeyExtractor()

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("认证", systemImage: "key")
                switch provider.credentialKind {
                case .sessionKey:
                    claudeCredentialContent
                case .apiKey:
                    apiKeyContent(platformID: provider.id)
                case .apiKeyAndConsoleCookie:
                    mimoCredentialContent
                case .codexLocalAuth:
                    codexContent
                }
            }
            .padding(4)
        }
        .sheet(isPresented: $isShowingMiMoConnector) {
            MiMoConsoleConnectionSheet(
                status: $miMoConnectorStatus,
                onConnected: { cookie in
                    do {
                        try KeychainHelper.saveMiMoConsoleCookie(cookie)
                        cookieInput = ""
                        miMoConnectorStatus = "已连接 MiMo 控制台。"
                        isShowingMiMoConnector = false
                        onChanged()
                    } catch {
                        miMoConnectorStatus = "保存 Cookie 失败：\(error.localizedDescription)"
                    }
                }
            )
        }
    }

    private var claudeCredentialContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Local JSONL scan info
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("本地用量自动扫描")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            Text("从 `~/.claude/projects/` 扫描 Claude Code session 日志，无需额外配置。点击上方刷新按钮更新数据。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Optional Session Key for claude.ai web quota
            Text("claude.ai Web 配额（可选）")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            StoredSecretRow(label: "Session Key", maskedValue: credentialSnapshot.maskedClaudeSessionKey)
            HStack {
                Picker("", selection: $selectedBrowser) {
                    ForEach(BrowserType.allCases) { browser in
                        Text(browser.rawValue).tag(browser)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                Button(isExtracting ? "提取中…" : "从浏览器提取") {
                    extractClaudeKey()
                }
                .disabled(isExtracting)
            }

            HStack {
                SecureField("粘贴 Claude session key", text: $claudeInput)
                    .textFieldStyle(.roundedBorder)
                Button("保存") {
                    saveClaudeKey()
                }
                .disabled(claudeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let extractionStatus {
                Text(extractionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @State private var openaiAdminKeyInput = ""

    private func apiKeyContent(platformID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StoredSecretRow(
                label: platformID == "mimo" ? "Token Plan / API Key" : "API Key",
                maskedValue: credentialSnapshot.maskedAPIKey(for: platformID)
            )
            HStack {
                SecureField(apiKeyPlaceholder(for: platformID), text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button("保存") {
                    let value = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    try? KeychainHelper.saveAPIKey(value, for: platformID)
                    if platformID == "mimo" {
                        MiMoAPIKeyRoleStore.saveRole(for: value)
                    }
                    apiKeyInput = ""
                    onChanged()
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(apiKeyHelpText(for: platformID))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if platformID == "openai" {
                Divider()
                StoredSecretRow(
                    label: "Admin Key",
                    maskedValue: credentialSnapshot.maskedOpenAIAdminKey
                )
                HStack {
                    SecureField("sk-…（组织 Admin）", text: $openaiAdminKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") {
                        let value = openaiAdminKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        try? KeychainHelper.saveOpenAIAdminKey(value)
                        openaiAdminKeyInput = ""
                        onChanged()
                    }
                    .disabled(openaiAdminKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("组织级 Admin API key，可查询用量、费用和余额。需要 Organization Admin 权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var mimoCredentialContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Token Plan Key
            VStack(alignment: .leading, spacing: 6) {
                StoredSecretRow(
                    label: "Token Plan Key",
                    maskedValue: credentialSnapshot.maskedMiMoTokenPlanKey
                )
                HStack {
                    SecureField("tp-…", text: $tokenPlanKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") {
                        let value = tokenPlanKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        try? KeychainHelper.saveMiMoTokenPlanKey(value)
                        tokenPlanKeyInput = ""
                        onChanged()
                    }
                    .disabled(tokenPlanKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Token Plan `tp-` key，用于套餐服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // API Key
            VStack(alignment: .leading, spacing: 6) {
                StoredSecretRow(
                    label: "API Key（按量付费）",
                    maskedValue: credentialSnapshot.maskedAPIKey(for: "mimo")
                )
                HStack {
                    SecureField("sk-…", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") {
                        let value = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        try? KeychainHelper.saveAPIKey(value, for: "mimo")
                        apiKeyInput = ""
                        onChanged()
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("按量付费 `sk-` key，暂无余额/用量查询接口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            mimoCredentialSummary
            Divider()
            Button {
                miMoConnectorStatus = "打开窗口后请登录 MiMo 控制台。"
                isShowingMiMoConnector = true
            } label: {
                Label("连接 MiMo 控制台", systemImage: "safari")
            }
            .help("打开 MiMo 控制台，登录成功后自动保存 Cookie。")

            StoredSecretRow(label: "Console Cookie", maskedValue: credentialSnapshot.maskedMiMoConsoleCookie)

            DisclosureGroup("手动粘贴 Cookie（高级）") {
                cookieContent
                    .padding(.top, 8)
            }
            .font(.caption)
        }
    }

    private var mimoCredentialSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if credentialSnapshot.hasMiMoTokenPlanKey {
                Label("Token Plan Key 已配置。", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if let role = credentialSnapshot.miMoAPIKeyRole {
                switch role {
                case .payAsYouGoAPIKey:
                    Label("按量 API Key 已配置，仅用于调用验证。", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                case .unknownAPIKey:
                    Label("API Key 已配置，类型未知。", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                case .tokenPlanKey:
                    // 旧迁移残留，理论上不会再出现
                    EmptyView()
                }
            }
            if credentialSnapshot.maskedMiMoConsoleCookie != nil {
                Label("Console Cookie 已配置，可查询 Token Plan 用量。", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else if !credentialSnapshot.hasMiMoTokenPlanCredential && credentialSnapshot.miMoAPIKeyRole == nil {
                Label("推荐连接控制台以查询 Token Plan 用量。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cookieContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SecureField("粘贴 MiMo Console Cookie", text: $cookieInput)
                    .textFieldStyle(.roundedBorder)
                Button("保存") {
                    let value = cookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    try? KeychainHelper.saveMiMoConsoleCookie(value)
                    cookieInput = ""
                    onChanged()
                }
                .disabled(cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("手动 Cookie 仅作为备用路径；推荐优先使用控制台自动连接。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var codexContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Codex 本地登录", systemImage: "terminal")
            let auth = CodexAuthReader.status()
            switch auth {
            case .configured(let email, let plan):
                InfoRow(label: "Email", value: email.isEmpty ? "未知" : email)
                InfoRow(label: "Plan", value: plan.capitalized)
                Text("Codex 优先读取 ChatGPT/Codex usage 限额，并在失败时回退本地 `~/.codex/sessions` 日志。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .expired:
                Label("认证已过期，请在 Terminal 运行 `codex login`。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .notConfigured:
                Label("未找到 Codex 登录信息，请在 Terminal 运行 `codex login`。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    codexLoginButton
                    codexFolderButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    codexLoginButton
                    codexFolderButton
                }
            }

            if let codexActionStatus {
                Text(codexActionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            sectionHeader("OpenAI Admin / API extras", systemImage: "network")
            StoredSecretRow(label: "Admin/API Key", maskedValue: credentialSnapshot.maskedCodexAdminKey)
            HStack {
                SecureField("sk-…", text: $codexAdminKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button("保存") {
                    saveCodexAdminKey()
                }
                .disabled(codexAdminKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("本地 Codex 用量不需要这个 key；它只用于可选 OpenAI Usage/Costs extras，通常需要组织或项目权限。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if credentialSnapshot.hasCodexAdminKey {
                Label("Extras key 已配置；刷新时会尝试查询 Usage/Costs。权限不足时不会覆盖本地 Codex 数据。", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("未配置 extras key；Codex 仍会使用 Codex 本地登录查询套餐和限额。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var codexLoginButton: some View {
        Button {
            runCodexLogin()
        } label: {
            Label("重新登录 Codex", systemImage: "terminal")
        }
    }

    private var codexFolderButton: some View {
        Button {
            openCodexFolder()
        } label: {
            Label("打开 ~/.codex", systemImage: "folder")
        }
    }

    private func extractClaudeKey() {
        isExtracting = true
        extractionStatus = nil
        Task {
            do {
                if let (browser, key) = try await extractor.extractFromBrowser(selectedBrowser) {
                    try await extractor.storeInKeychain(sessionKey: key)
                    try await extractor.writeConfigFile(sessionKey: key)
                    extractionStatus = "已从 \(browser.rawValue) 提取并保存"
                    onChanged()
                } else {
                    extractionStatus = "未在 \(selectedBrowser.rawValue) 找到 session key"
                }
            } catch {
                extractionStatus = error.localizedDescription
            }
            isExtracting = false
        }
    }

    private func saveClaudeKey() {
        let value = claudeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task {
            do {
                try await extractor.storeInKeychain(sessionKey: value)
                try await extractor.writeConfigFile(sessionKey: value)
                claudeInput = ""
                extractionStatus = "已保存 Claude session key"
                onChanged()
            } catch {
                extractionStatus = error.localizedDescription
            }
        }
    }

    private func saveCodexAdminKey() {
        let value = codexAdminKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try KeychainHelper.saveCodexAdminKey(value)
            codexAdminKeyInput = ""
            codexActionStatus = "已保存 OpenAI Admin/API extras key。"
            onChanged()
        } catch {
            codexActionStatus = "保存 extras key 失败：\(error.localizedDescription)"
        }
    }

    private func runCodexLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "codex login"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            codexActionStatus = "已在 Terminal 打开 `codex login`。"
        } catch {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("codex login", forType: .string)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
            codexActionStatus = "无法自动执行命令，已复制 `codex login` 并打开 Terminal。"
        }
    }

    private func openCodexFolder() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex")
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            } catch {
                codexActionStatus = "无法创建 ~/.codex：\(error.localizedDescription)"
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
        codexActionStatus = "已打开 ~/.codex。"
    }

    private func apiKeyPlaceholder(for platformID: String) -> String {
        switch platformID {
        case "openai":     return "sk-…"
        case "gemini":     return "AIza…"
        case "deepseek":   return "sk-…"
        case "anthropic":  return "sk-ant-…"
        case "minimax":    return "Token Plan key 或 Open Platform key"
        case "mimo":       return "sk-…"
        case "moonshot":   return "sk-…"
        case "openrouter": return "sk-or-…"
        case "qwen":       return "sk-…"
        default:           return "API key"
        }
    }

    private func apiKeyHelpText(for platformID: String) -> String {
        switch platformID {
        case "openai":     return "OpenAI 普通 API key 可验证调用能力；组织用量/费用查询需要额外权限。"
        case "gemini":     return "Gemini API key 可验证调用能力；费用侧建议接 Google Cloud Billing。"
        case "deepseek":   return "DeepSeek API key 可用于官方余额接口。"
        case "anthropic":  return "Anthropic 普通 API key 可验证调用能力；费用报告需要 Console 权限。"
        case "minimax":    return "MiniMax Token Plan key 可查询 remains；普通 Open Platform key 只能验证调用，公开 API 暂不能查余额。"
        case "mimo":       return "MiMo `tp-` key 用于套餐服务；`sk-` key 仅验证调用能力。用量查询需连接控制台 Cookie。"
        case "moonshot":   return "Moonshot / Kimi API key，可查询账户余额。支持国际和国内 endpoint。"
        case "openrouter": return "OpenRouter API key，可查询 credits 余额。"
        case "qwen":       return "阿里云 DashScope API key，可查询账户余额。"
        default:           return "输入平台 API key。"
        }
    }
}

private struct PlatformCapabilityPanel: View {
    let provider: ProviderCapability
    @State private var isExpanded = false

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    sectionHeader("查询能力", systemImage: "chart.bar.doc.horizontal")
                    Spacer()
                    Text(provider.usageCapability.displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                InfoRow(label: "凭据", value: provider.credentialKind.displayTitle)

                DisclosureGroup("查看说明", isExpanded: $isExpanded) {
                    Text(provider.usageCapability.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.caption)
            }
            .padding(4)
        }
    }
}

private struct PlatformMetricsPanel: View {
    let provider: ProviderCapability
    let service: Service?
    let dataStatus: ProviderDataStatus
    @State private var isDetailExpanded = false

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("当前数据", systemImage: "gauge.with.dots.needle.67percent")
                if let service, dataStatus == .ready {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(service.quotas.enumerated()), id: \.offset) { _, quota in
                            QuotaStatusRow(quota: quota)
                        }
                        if let session = service.currentSession {
                            SessionStatusRow(session: session)
                        }
                        if provider.id == "claude", let session = service.currentSession, let models = session.modelBreakdown, !models.isEmpty {
                            Divider()
                            claudeModelBreakdown(models)
                        }
                        if provider.id == "codex" {
                            Divider()
                            codexRateLimitPanel(service)
                        }
                        if provider.id == "deepseek" {
                            Divider()
                            deepseekBalancePanel(service)
                        }
                        if provider.id == "mimo" {
                            Divider()
                            mimoCreditPanel(service)
                        }
                        if provider.id == "openai" {
                            Divider()
                            openaiCostsPanel(service)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(dataStatus.title(for: provider.id), systemImage: dataStatus.systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(dataStatus.color)
                        DisclosureGroup("查看详情", isExpanded: $isDetailExpanded) {
                            Text(dataStatus.detail(for: provider.id))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 3)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func claudeModelBreakdown(_ models: [ModelUsage]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("模型用量")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(Array(models.enumerated()), id: \.offset) { _, usage in
                let total = (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
                HStack(spacing: 8) {
                    Text(shortModelName(usage.model))
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(formatTokenCount(total))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func shortModelName(_ model: String) -> String {
        // "claude-opus-4-7" → "opus-4-7"
        // "mimo-v2.5-pro-ultraspeed" → "mimo-v2.5-pro-ultraspeed"
        if model.hasPrefix("claude-") {
            return String(model.dropFirst("claude-".count))
        }
        return model
    }

    private func formatTokenCount(_ count: Double) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", count / 1_000_000) }
        if count >= 1_000 { return String(format: "%.0fK", count / 1_000) }
        return String(format: "%.0f", count)
    }

    // MARK: - Codex rate limit panel

    private func codexRateLimitPanel(_ service: Service) -> some View {
        let timeQuotas = service.quotas.filter { $0.type == .time }
        guard !timeQuotas.isEmpty else { return EmptyView().eraseToAnyView() }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Rate Limit 窗口")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(Array(timeQuotas.enumerated()), id: \.offset) { _, quota in
                codexRateLimitRow(quota)
            }
            if let session = service.currentSession, let tokens = session.tokens, tokens > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("本月总用量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTokenCount(tokens))
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            }
        }.eraseToAnyView()
    }

    private func codexRateLimitRow(_ quota: Quota) -> some View {
        let fraction = quota.usedFraction
        let remaining = quota.remaining
        let label = quota.total.map { total in
            if total >= 604_800 { return "7 天窗口" }
            if total >= 18_000 { return "5 小时窗口" }
            return "限制窗口"
        } ?? "限制窗口"

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Text(formatDuration(remaining))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(fraction > 0.85 ? .red : fraction > 0.65 ? .yellow : .green)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    // MARK: - DeepSeek balance panel

    private func deepseekBalancePanel(_ service: Service) -> some View {
        guard let quota = service.quotas.first(where: { $0.type == .money }) else {
            return EmptyView().eraseToAnyView()
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("账户余额")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "yensign.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f", quota.remaining))
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(.primary)
                Text(quota.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }.eraseToAnyView()
    }

    // MARK: - MiMo credit panel

    private func mimoCreditPanel(_ service: Service) -> some View {
        guard let quota = service.quotas.first(where: { $0.type == .monthlyTokens }) else {
            return EmptyView().eraseToAnyView()
        }

        let fraction = quota.usedFraction
        let used = quota.used
        let total = quota.total ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            Text("套餐用量")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                Text(formatTokenCount(used))
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatTokenCount(total))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.caption.monospaced())
                    .foregroundStyle(fraction > 0.85 ? .red : fraction > 0.65 ? .orange : .secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(fraction > 0.85 ? .red : fraction > 0.65 ? .yellow : .green)
            if let resetsAt = quota.resetsAt {
                Text("重置: \(formatResetsAt(resetsAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }.eraseToAnyView()
    }

    private func formatResetsAt(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        return df.string(from: date)
    }

    // MARK: - OpenAI costs panel

    private func openaiCostsPanel(_ service: Service) -> some View {
        let creditsQuota = service.quotas.first(where: { $0.type == .money })
        let costQuota = service.quotas.first(where: { $0.type == .costSpent })

        guard creditsQuota != nil || costQuota != nil else {
            return EmptyView().eraseToAnyView()
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("组织用量")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if let q = creditsQuota {
                HStack {
                    Image(systemName: "creditcard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("余额")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", q.remaining))
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            }
            if let q = costQuota {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("近 30 天费用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", q.used))
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            }
        }.eraseToAnyView()
    }
}

// MARK: - View erase helper

extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}


enum ProviderCredentialStatus: Equatable {
    case configured
    case expired
    case notConfigured

    var title: String {
        switch self {
        case .configured:    return "已配置"
        case .expired:       return "认证过期"
        case .notConfigured: return "未配置"
        }
    }

    var color: Color {
        switch self {
        case .configured:    return .green
        case .expired:       return .orange
        case .notConfigured: return .secondary
        }
    }
}

private enum CredentialStatusReader {
    static func status(
        for provider: ProviderCapability,
        snapshot: ProviderCredentialSnapshot
    ) -> ProviderCredentialStatus {
        switch provider.credentialKind {
        case .sessionKey, .apiKey, .apiKeyAndConsoleCookie:
            return snapshot.status(for: provider) == .configured ? .configured : .notConfigured
        case .codexLocalAuth:
            switch CodexAuthReader.status() {
            case .configured:    return .configured
            case .expired:       return .expired
            case .notConfigured: return .notConfigured
            }
        }
    }
}

enum CodexAuthStatus: Equatable {
    case configured(email: String, plan: String)
    case expired
    case notConfigured
}

enum CodexAuthReader {
    static func status() -> CodexAuthStatus {
        let authPath = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard
            let data = FileManager.default.contents(atPath: authPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String,
            let accessToken = tokens["access_token"] as? String,
            let payload = decodeJWTPayload(idToken)
        else { return .notConfigured }

        guard
            let accessPayload = decodeJWTPayload(accessToken),
            let exp = accessPayload["exp"] as? TimeInterval,
            Date().timeIntervalSince1970 < exp - 60
        else { return .expired }

        let claim = codexAuthClaim(from: payload)
        return .configured(
            email: claim.email ?? "",
            plan: claim.plan ?? "unknown"
        )
    }
}
