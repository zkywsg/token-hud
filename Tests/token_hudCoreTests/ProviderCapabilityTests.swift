import Testing
@testable import token_hudCore

@Suite("ProviderCapability")
struct ProviderCapabilityTests {
    @Test func openAIAnthropicAndGeminiDoNotPromiseUsageForPlainAPIKeys() {
        for id in ["openai", "anthropic", "gemini"] {
            let capability = ProviderCapability.catalog[id]

            #expect(capability?.credentialKind == .apiKey)
            #expect(capability?.usageCapability == .apiKeyValidationOnly)
            #expect(capability?.resetActions == [.credential, .serviceData])
        }
    }

    @Test func directUsageProvidersExposeConcreteCapabilities() throws {
        #expect(ProviderCapability.catalog["deepseek"]?.usageCapability == .balanceEndpoint)
        #expect(ProviderCapability.catalog["minimax"]?.usageCapability == .tokenPlanEndpoint)
    }

    @Test func codexUsesLocalAuthAndSessionLogs() throws {
        let codex = try #require(ProviderCapability.catalog["codex"])

        #expect(codex.credentialKind == .codexLocalAuth)
        #expect(codex.usageCapability == .localSessionLogs)
        #expect(codex.resetActions == [.localAuth, .adminAPIKey, .serviceData])
    }

    @Test func codexAdminKeyIsAnOptionalExtraCredential() {
        let snapshot = ProviderCredentialSnapshot(
            claudeSessionKey: nil,
            apiKeys: [:],
            mimoConsoleCookie: nil,
            codexAdminKey: "sk-admin-secret-1234567890"
        )

        #expect(snapshot.hasCodexAdminKey)
        #expect(snapshot.maskedCodexAdminKey == "sk-adm••••7890")
        #expect(snapshot.status(for: ProviderCapability.catalog["codex"]!) == .notConfigured)
    }

    @Test func mimoSeparatesAPIKeyAndConsoleCookie() throws {
        let mimo = try #require(ProviderCapability.catalog["mimo"])

        #expect(mimo.credentialKind == .apiKeyAndConsoleCookie)
        #expect(mimo.usageCapability == .consoleCookieTokenPlan)
        #expect(mimo.resetActions == [.apiKey, .consoleCookie, .serviceData])
    }

    @Test func serviceDataStatusDistinguishesMissingEmptyErrorAndReady() {
        #expect(ProviderDataStatus.status(for: nil) == .notQueried)

        let empty = Service(label: "OpenAI", quotas: [], currentSession: nil)
        #expect(ProviderDataStatus.status(for: empty) == .noUsageData)

        let unsupported = Service(
            label: "OpenAI",
            quotas: [],
            currentSession: nil,
            error: ProviderQueryError.usageUnsupported.rawValue
        )
        #expect(ProviderDataStatus.status(for: unsupported) == .usageUnsupported)

        let ready = Service(
            label: "DeepSeek",
            quotas: [Quota(type: .money, total: 10, used: 2, unit: "USD", resetsAt: nil)],
            currentSession: nil
        )
        #expect(ProviderDataStatus.status(for: ready) == .ready)
    }

    @Test func serviceDataStatusClassifiesLegacyFetcherErrorStrings() {
        let network = Service(label: "MiniMax", quotas: [], currentSession: nil, error: "Network error: timed out")
        let invalid = Service(label: "DeepSeek", quotas: [], currentSession: nil, error: "Invalid API key")
        let expired = Service(label: "MiMo", quotas: [], currentSession: nil, error: "Console login expired")
        let miniMaxNoTokenPlan = Service(
            label: "MiniMax",
            quotas: [],
            currentSession: nil,
            error: "no active token plan subscription"
        )
        let legacyNoSessions = Service(label: "Codex", quotas: [], currentSession: nil, error: "No sessions yet")
        let normalizedNoSessions = Service(
            label: "Codex",
            quotas: [],
            currentSession: nil,
            error: ProviderQueryError.noLocalSessions.rawValue
        )

        #expect(ProviderDataStatus.status(for: network) == .networkError)
        #expect(ProviderDataStatus.status(for: invalid) == .permissionDenied)
        #expect(ProviderDataStatus.status(for: expired) == .tokenExpired)
        #expect(ProviderDataStatus.status(for: miniMaxNoTokenPlan) == .usageUnsupported)
        #expect(ProviderDataStatus.status(for: legacyNoSessions) == .noUsageData)
        #expect(ProviderDataStatus.status(for: normalizedNoSessions) == .noUsageData)
    }

    @Test func credentialSnapshotComputesStatusWithoutExposingSecrets() {
        let snapshot = ProviderCredentialSnapshot(
            claudeSessionKey: "sk-ant-abcdefghijklmnopqrstuvwxyz",
            apiKeys: ["openai": "sk-openai-secret-1234567890"],
            mimoConsoleCookie: "session=abcdef1234567890"
        )

        #expect(snapshot.status(for: ProviderCapability.catalog["claude"]!) == .configured)
        #expect(snapshot.status(for: ProviderCapability.catalog["openai"]!) == .configured)
        #expect(snapshot.status(for: ProviderCapability.catalog["mimo"]!) == .configured)
        #expect(snapshot.maskedClaudeSessionKey == "sk-ant••••wxyz")
        #expect(snapshot.maskedAPIKey(for: "openai") == "sk-ope••••7890")
        #expect(snapshot.maskedMiMoConsoleCookie == "sessio••••7890")
    }

    @Test func credentialSnapshotTreatsMimoCookieAsConfigured() {
        let snapshot = ProviderCredentialSnapshot(
            claudeSessionKey: nil,
            apiKeys: [:],
            mimoConsoleCookie: "session=abcdef1234567890"
        )

        #expect(snapshot.status(for: ProviderCapability.catalog["mimo"]!) == .configured)
        #expect(snapshot.status(for: ProviderCapability.catalog["openai"]!) == .notConfigured)
    }

    @Test func mimoCredentialSnapshotDistinguishesTokenPlanKeyAPIKeyAndConsoleCookie() {
        let tokenPlan = ProviderCredentialSnapshot(
            claudeSessionKey: nil,
            apiKeys: ["mimo": "tp-secret-token-plan"],
            mimoConsoleCookie: nil
        )
        let payAsYouGo = ProviderCredentialSnapshot(
            claudeSessionKey: nil,
            apiKeys: ["mimo": "sk-secret-payg"],
            mimoConsoleCookie: nil
        )
        let consoleCookie = ProviderCredentialSnapshot(
            claudeSessionKey: nil,
            apiKeys: [:],
            mimoConsoleCookie: "session=abcdef1234567890"
        )

        #expect(tokenPlan.miMoAPIKeyRole == .tokenPlanKey)
        #expect(tokenPlan.hasMiMoTokenPlanCredential)
        #expect(payAsYouGo.miMoAPIKeyRole == .payAsYouGoAPIKey)
        #expect(!payAsYouGo.hasMiMoTokenPlanCredential)
        #expect(consoleCookie.miMoAPIKeyRole == nil)
        #expect(consoleCookie.hasMiMoTokenPlanCredential)
    }
}
