import SwiftUI

struct PlatformResetPanel: View {
    let provider: ProviderCapability
    let credentialStatus: ProviderCredentialStatus
    let onCredentialChanged: () -> Void
    let onClearData: () -> Void
    @State private var isConfirmingLocalAuthRemoval = false

    var body: some View {
        GlassPanel {
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
                if provider.id == "openai" {
                    try? KeychainHelper.deleteOpenAIAdminKey()
                } else {
                    try? KeychainHelper.deleteCodexAdminKey()
                }
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
