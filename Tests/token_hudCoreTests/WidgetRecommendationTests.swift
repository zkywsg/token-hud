import Testing
@testable import token_hudCore

@Suite("Widget recommendation")
struct WidgetRecommendationTests {
    @Test func configuredUsageProvidersGenerateRecommendedWidgets() {
        let snapshot = ProviderCredentialSnapshot(
            claudeSessionKey: "claude-session",
            apiKeys: [
                "codex": "ignored",
                "deepseek": "sk-deepseek",
                "mimo": "tp-mimo",
                "openai": "sk-openai",
                "gemini": "AIza",
                "anthropic": "sk-ant"
            ],
            mimoConsoleCookie: nil
        )

        let recommendations = WidgetRecommendationEngine.recommendations(for: snapshot)

        #expect(recommendations.contains(WidgetDescriptor(service: "claude", metric: "remaining_time", style: "bar", quotaIndex: 0)))
        #expect(recommendations.contains(WidgetDescriptor(service: "deepseek", metric: "balance", style: "text", quotaIndex: 0)))
        #expect(recommendations.contains(WidgetDescriptor(service: "mimo", metric: "credits_used", style: "bar", quotaIndex: 0)))
        #expect(!recommendations.contains { $0.service == "openai" })
        #expect(!recommendations.contains { $0.service == "gemini" })
        #expect(!recommendations.contains { $0.service == "anthropic" })
    }

    @Test func miniMaxPlainAPIKeyDoesNotGenerateUsageWidgetsWithoutQuotaEvidence() {
        let snapshot = ProviderCredentialSnapshot(
            claudeSessionKey: nil,
            apiKeys: ["minimax": "saved-open-platform-key"],
            mimoConsoleCookie: nil
        )

        let recommendations = WidgetRecommendationEngine.recommendations(for: snapshot)

        #expect(!recommendations.contains { $0.service == "minimax" })
    }

    @Test func miniMaxQuotaEvidenceGeneratesUsageWidgets() {
        let snapshot = ProviderCredentialSnapshot(
            claudeSessionKey: nil,
            apiKeys: ["minimax": "saved-open-platform-key"],
            mimoConsoleCookie: nil
        )
        let state = StateFile(
            version: 1,
            updatedAt: "2026-06-08T00:00:00Z",
            services: [
                "minimax": Service(
                    label: "MiniMax",
                    quotas: [
                        Quota(type: .monthlyTokens, total: 1_000_000, used: 250_000, unit: "tokens", resetsAt: nil)
                    ],
                    currentSession: nil
                )
            ]
        )

        let recommendations = WidgetRecommendationEngine.recommendations(for: snapshot, state: state)

        #expect(recommendations.contains(WidgetDescriptor(service: "minimax", metric: "monthly_tokens", style: "bar", quotaIndex: 0)))
        #expect(recommendations.contains(WidgetDescriptor(service: "minimax", metric: "usage_percent", style: "text", quotaIndex: 0)))
    }

    @Test func recommendationsCanSupplementWithoutDuplicatingExistingWidgets() {
        let existing = [
            WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 0),
            WidgetDescriptor(service: "deepseek", metric: "balance", style: "text", quotaIndex: 0)
        ]
        let recommended = [
            WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 0),
            WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 1),
            WidgetDescriptor(service: "deepseek", metric: "balance", style: "text", quotaIndex: 0)
        ]

        let supplemented = WidgetRecommendationEngine.supplement(existing: existing, with: recommended)

        #expect(supplemented == [
            WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 0),
            WidgetDescriptor(service: "deepseek", metric: "balance", style: "text", quotaIndex: 0),
            WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 1)
        ])
    }

    @Test func serviceGroupsPreserveFirstAppearanceAndWidgetOrder() {
        let widgets = [
            WidgetDescriptor(id: "codex-5h", service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 0),
            WidgetDescriptor(id: "claude-time", service: "claude", metric: "remaining_time", style: "bar", quotaIndex: 0),
            WidgetDescriptor(id: "codex-7d", service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 1),
            WidgetDescriptor(id: "mimo-plan", service: "mimo", metric: "plan_name", style: "text", quotaIndex: 0),
            WidgetDescriptor(id: "claude-session", service: "claude", metric: "session_tokens", style: "text", quotaIndex: 0)
        ]

        let groups = WidgetServiceGrouping.groups(for: widgets)

        #expect(groups.map(\.service) == ["codex", "claude", "mimo"])
        #expect(groups[0].widgets.map(\.id) == ["codex-5h", "codex-7d"])
        #expect(groups[1].widgets.map(\.id) == ["claude-time", "claude-session"])
        #expect(groups[2].widgets.map(\.id) == ["mimo-plan"])
    }
}
