import SwiftUI

struct PlatformListView: View {
    @Environment(StateWatcher.self) private var stateWatcher
    @Environment(CodexFetcher.self) private var codexFetcher
    @Environment(APIPlatformFetcher.self) private var apiPlatformFetcher

    @State private var selectedPlatformID = "codex"
    @State private var revision = 0
    @State private var resetMessage: String?
    @State private var credentialSnapshot = ProviderCredentialSnapshot.empty
    @State private var authorizationNeededPlatformIDs = Set<String>()

    private var selectedProvider: ProviderCapability {
        ProviderCapability.catalog[selectedPlatformID] ?? ProviderCapability.all[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            platformSidebar
                .frame(width: 260)
            Divider()
            PlatformDetailView(
                provider: selectedProvider,
                service: stateWatcher.currentState?.services[selectedProvider.id],
                revision: revision,
                credentialSnapshot: credentialSnapshot,
                needsAuthorization: authorizationNeededPlatformIDs.contains(selectedProvider.id),
                onCredentialChanged: {
                    reloadCredentialSnapshot()
                    authorizationNeededPlatformIDs.remove(selectedProvider.id)
                    resetMessage = "已保存认证；刷新会先静默查询。"
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
        .overlay(alignment: .bottom) {
            if let resetMessage {
                Text(resetMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func refresh(provider: ProviderCapability, allowUserInteraction: Bool) {
        Task {
            switch provider.credentialKind {
            case .codexLocalAuth:
                await codexFetcher.fetch(allowUserInteraction: allowUserInteraction)
                authorizationNeededPlatformIDs.remove(provider.id)
            case .apiKey, .apiKeyAndConsoleCookie:
                let result = await apiPlatformFetcher.fetchSingle(
                    platform: provider.id,
                    allowUserInteraction: allowUserInteraction
                )
                handleRefreshResult(result, provider: provider)
            case .sessionKey:
                break
            }
            stateWatcher.readNow()
        }
    }

    private func handleRefreshResult(
        _ result: APIPlatformFetcher.SingleFetchResult,
        provider: ProviderCapability
    ) {
        switch result {
        case .updated:
            authorizationNeededPlatformIDs.remove(provider.id)
            resetMessage = "已刷新 \(provider.displayName)"
        case .needsAuthorization:
            authorizationNeededPlatformIDs.insert(provider.id)
            resetMessage = "\(provider.displayName) 需要授权刷新"
        case .noCredential:
            authorizationNeededPlatformIDs.remove(provider.id)
            resetMessage = "\(provider.displayName) 未配置认证"
        case .noData:
            resetMessage = "\(provider.displayName) 暂无可更新数据"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            resetMessage = nil
        }
    }

    private func reloadCredentialSnapshot() {
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
            codexAdminKey: KeychainHelper.hasCodexAdminKey() ? "saved" : nil
        )
        revision += 1
    }

    private func clearData(for platformID: String) {
        do {
            try StateServiceResetter.clearService(platformID)
            stateWatcher.readNow()
            resetMessage = "已清空 \(ProviderCapability.catalog[platformID]?.displayName ?? platformID) 数据"
        } catch {
            resetMessage = error.localizedDescription
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            resetMessage = nil
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

    private var dataStatus: ProviderDataStatus {
        ProviderDataStatus.status(for: service)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    Text(provider.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    StatusDot(color: credentialStatus.color)
                }
                StatusPill(
                    title: needsAuthorization ? "需授权" : dataStatus.title(for: provider.id),
                    color: needsAuthorization ? .orange : dataStatus.color
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(provider.displayName)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    StatusPill(title: credentialStatus.title, color: credentialStatus.color)
                    StatusPill(title: dataStatus.title(for: provider.id), color: dataStatus.color)
                    if needsAuthorization {
                        StatusPill(title: "需要授权刷新", color: .orange)
                    }
                }
            }
            Spacer()
            if needsAuthorization {
                Button {
                    onAuthorizeRefresh()
                } label: {
                    Label("授权刷新", systemImage: "key")
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
        GroupBox {
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
            }
        }
    }

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
        }
    }

    private var mimoCredentialContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            apiKeyContent(platformID: provider.id)
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
            switch credentialSnapshot.miMoAPIKeyRole {
            case .tokenPlanKey:
                Label("Token Plan Key 已配置，可用于套餐服务。", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .payAsYouGoAPIKey:
                Label("按量 API Key 已配置，仅用于调用验证。", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            case .unknownAPIKey:
                Label("API Key 已配置，但无法判断是否为 Token Plan Key。", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            case nil:
                Label("未配置 MiMO API Key。", systemImage: "key")
                    .foregroundStyle(.secondary)
            }

            if credentialSnapshot.maskedMiMoConsoleCookie != nil {
                Label("Console Cookie 已配置，可查询控制台 Token Plan。", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else if !credentialSnapshot.hasMiMoTokenPlanCredential {
                Label("未配置套餐查询凭据；推荐使用 Token Plan Key 或连接控制台。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
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
            case .expired:
                Label("认证已过期，请在 Terminal 运行 `codex login`。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .notConfigured:
                Label("未找到 Codex 登录信息，请在 Terminal 运行 `codex login`。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    runCodexLogin()
                } label: {
                    Label("重新登录 Codex", systemImage: "terminal")
                }

                Button {
                    openCodexFolder()
                } label: {
                    Label("打开 ~/.codex", systemImage: "folder")
                }
            }

            if let codexActionStatus {
                Text(codexActionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            if credentialSnapshot.hasCodexAdminKey {
                Label("Extras key 已配置；刷新时会尝试查询 Usage/Costs。权限不足时不会覆盖本地 Codex 数据。", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("未配置 extras key；Codex 仍会使用 Codex 本地登录查询套餐和限额。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        case "openai":    return "sk-…"
        case "gemini":    return "AIza…"
        case "deepseek":  return "sk-…"
        case "anthropic": return "sk-ant-…"
        case "minimax":   return "Token Plan key 或 Open Platform key"
        case "mimo":      return "tp-… 或 sk-…"
        default:          return "API key"
        }
    }

    private func apiKeyHelpText(for platformID: String) -> String {
        switch platformID {
        case "openai":    return "OpenAI 普通 API key 可验证调用能力；组织用量/费用查询需要额外权限。"
        case "gemini":    return "Gemini API key 可验证调用能力；费用侧建议接 Google Cloud Billing。"
        case "deepseek":  return "DeepSeek API key 可用于官方余额接口。"
        case "anthropic": return "Anthropic 普通 API key 可验证调用能力；费用报告需要 Console 权限。"
        case "minimax":   return "MiniMax Token Plan key 可查询 remains；普通 Open Platform key 只能验证调用，公开 API 暂不能查余额。"
        case "mimo":      return "MiMo `tp-` Token Plan key 用于套餐服务；`sk-` 按量 key 只验证调用能力。"
        default:          return "输入平台 API key。"
        }
    }
}

private struct PlatformCapabilityPanel: View {
    let provider: ProviderCapability
    @State private var isExpanded = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    sectionHeader("查询能力", systemImage: "chart.bar.doc.horizontal")
                    Spacer()
                    Text(provider.usageCapability.displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

    var body: some View {
        GroupBox {
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
                    }
                } else {
                    Label(dataStatus.detail(for: provider.id), systemImage: dataStatus.systemImage)
                        .font(.caption)
                        .foregroundStyle(dataStatus.color)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PlatformResetPanel: View {
    let provider: ProviderCapability
    let credentialStatus: ProviderCredentialStatus
    let onCredentialChanged: () -> Void
    let onClearData: () -> Void
    @State private var isConfirmingLocalAuthRemoval = false

    var body: some View {
        GroupBox {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    resetButtons
                    resetHelpText
                }
                .padding(.top, 8)
            } label: {
                sectionHeader("重置与清理", systemImage: "arrow.counterclockwise")
            }
            .padding(4)
        }
        .confirmationDialog(
            "移除 Codex 本地认证？",
            isPresented: $isConfirmingLocalAuthRemoval,
            titleVisibility: .visible
        ) {
            Button("移除 ~/.codex/auth.json", role: .destructive) {
                removeCodexLocalAuth()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会让 Codex CLI 退出登录；sessions 不会被删除。之后需要重新运行 `codex login`。")
        }
    }

    private var resetButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                resetButtonContent
            }
            VStack(alignment: .leading, spacing: 8) {
                resetButtonContent
            }
        }
    }

    @ViewBuilder
    private var resetButtonContent: some View {
        if provider.resetActions.contains(.credential) {
            Button(role: .destructive) {
                resetCredential()
            } label: {
                Label("重置认证", systemImage: "key.slash")
            }
            .disabled(credentialStatus == .notConfigured)
        }
        if provider.resetActions.contains(.apiKey) {
            Button(role: .destructive) {
                try? KeychainHelper.deleteAPIKey(for: provider.id)
                if provider.id == "mimo" {
                    MiMoAPIKeyRoleStore.clear()
                }
                onCredentialChanged()
            } label: {
                Label("重置 API Key", systemImage: "key.slash")
            }
        }
        if provider.resetActions.contains(.consoleCookie) {
            Button(role: .destructive) {
                try? KeychainHelper.deleteMiMoConsoleCookie()
                onCredentialChanged()
            } label: {
                Label("重置 Cookie", systemImage: "text.badge.xmark")
            }
        }
        if provider.resetActions.contains(.localAuth) {
            Button(role: .destructive) {
                isConfirmingLocalAuthRemoval = true
            } label: {
                Label("移除本地认证", systemImage: "person.crop.circle.badge.xmark")
            }
        }
        if provider.resetActions.contains(.adminAPIKey) {
            Button(role: .destructive) {
                try? KeychainHelper.deleteCodexAdminKey()
                onCredentialChanged()
            } label: {
                Label("重置 Admin Key", systemImage: "key.slash")
            }
        }
        if provider.resetActions.contains(.serviceData) {
            Button(role: .destructive) {
                onClearData()
            } label: {
                Label("清空数据", systemImage: "trash")
            }
        }
    }

    private var resetHelpText: some View {
        Group {
            if provider.credentialKind == .codexLocalAuth {
                Text("Codex 认证由 Codex 自身管理；这里不会删除 `~/.codex/auth.json`。")
            } else {
                Text("重置认证会删除 Keychain 凭据；清空数据只删除 state.json 中当前平台的数据。")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func resetCredential() {
        switch provider.credentialKind {
        case .sessionKey:
            try? KeychainHelper.deleteClaudeSessionKey()
        case .apiKey:
            try? KeychainHelper.deleteAPIKey(for: provider.id)
            if provider.id == "openai" {
                try? KeychainHelper.deleteLegacyOpenAIKey()
            }
        case .apiKeyAndConsoleCookie:
            try? KeychainHelper.deleteAPIKey(for: provider.id)
            try? KeychainHelper.deleteMiMoConsoleCookie()
            MiMoAPIKeyRoleStore.clear()
        case .codexLocalAuth:
            break
        }
        onCredentialChanged()
    }

    private func removeCodexLocalAuth() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
        onCredentialChanged()
    }
}

private enum ProviderCredentialStatus: Equatable {
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

enum CodexAuthReader {
    static func status() -> CodexAuthStatus {
        let authPath = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard
            let data = FileManager.default.contents(atPath: authPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String,
            let accessToken = tokens["access_token"] as? String,
            let payload = decodeJWT(idToken)
        else { return .notConfigured }

        guard
            let accessPayload = decodeJWT(accessToken),
            let exp = accessPayload["exp"] as? TimeInterval,
            Date().timeIntervalSince1970 < exp - 60
        else { return .expired }

        let claim = codexAuthClaim(from: payload)
        return .configured(
            email: claim.email ?? "",
            plan: claim.plan ?? "unknown"
        )
    }

    private static func decodeJWT(_ token: String) -> [String: Any]? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder > 0 {
            b64 += String(repeating: "=", count: 4 - remainder)
        }
        guard
            let data = Data(base64Encoded: b64),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }
}

private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct StoredSecretRow: View {
    let label: String
    let maskedValue: String?

    var body: some View {
        InfoRow(label: label, value: maskedValue ?? "未配置")
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .trailing)
                .minimumScaleFactor(0.82)
        }
    }
}

private struct QuotaStatusRow: View {
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

private struct SessionStatusRow: View {
    let session: SessionSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text(sessionText)
                .font(.caption)
                .foregroundStyle(.secondary)
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

private func sectionHeader(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
}

private extension ProviderCapability {
    var canRefresh: Bool {
        credentialKind == .codexLocalAuth ||
        credentialKind == .apiKey ||
        credentialKind == .apiKeyAndConsoleCookie
    }
}

private extension ProviderCredentialKind {
    var displayTitle: String {
        switch self {
        case .sessionKey:             return "Session Key"
        case .apiKey:                 return "API Key"
        case .codexLocalAuth:         return "Codex 本地认证"
        case .apiKeyAndConsoleCookie: return "API Key + Console Cookie"
        }
    }
}

private extension ProviderUsageCapability {
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

private extension ProviderDataStatus {
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
