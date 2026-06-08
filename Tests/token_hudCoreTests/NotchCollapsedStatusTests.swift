import Testing
@testable import token_hudCore

@Suite("Notch collapsed status")
struct NotchCollapsedStatusTests {
    @Test func configuredLeadingAndTrailingSourcesAreComputedSeparately() {
        let state = StateFile(
            version: 1,
            updatedAt: "2026-06-07T00:00:00Z",
            services: [
                "codex": Service(
                    label: "Codex Plus",
                    quotas: [
                        Quota(type: .time, total: 100, used: 25, unit: "seconds", resetsAt: nil),
                        Quota(type: .time, total: 100, used: 60, unit: "seconds", resetsAt: nil)
                    ],
                    currentSession: nil
                )
            ]
        )
        let widgets = [
            WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 0),
            WidgetDescriptor(service: "codex", metric: "remaining_time", style: "bar", quotaIndex: 1)
        ]
        let configuration = NotchCollapsedStatusConfiguration(
            leading: .widget(widgets[0].id),
            trailing: .widget(widgets[1].id)
        )

        let value = NotchCollapsedStatusEngine.value(widgets: widgets, state: state, configuration: configuration)

        #expect(value.leadingFraction == 0.25)
        #expect(value.trailingText == "60%")
    }

    @Test func missingConfiguredSourceFallsBackToAutomaticValue() {
        let state = StateFile(
            version: 1,
            updatedAt: "2026-06-07T00:00:00Z",
            services: [
                "deepseek": Service(
                    label: "DeepSeek",
                    quotas: [Quota(type: .money, total: 20, used: 5, unit: "USD", resetsAt: nil)],
                    currentSession: nil
                )
            ]
        )
        let widgets = [
            WidgetDescriptor(service: "deepseek", metric: "balance", style: "text", quotaIndex: 0)
        ]
        let configuration = NotchCollapsedStatusConfiguration(
            leading: .widget("missing-widget-id"),
            trailing: .widget("missing-widget-id")
        )

        let value = NotchCollapsedStatusEngine.value(widgets: widgets, state: state, configuration: configuration)

        #expect(value.leadingFraction == 0.25)
        #expect(value.trailingText == "25%")
    }
}
