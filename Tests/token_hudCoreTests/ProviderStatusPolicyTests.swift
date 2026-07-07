import Testing
@testable import token_hudCore

@Suite("ProviderStatusPolicy")
struct ProviderStatusPolicyTests {
    @Test func endpointHealthDoesNotTreatAuthOrUnsupportedMethodAsOperational() {
        #expect(ProviderStatusPolicy.endpointStatus(forHTTPStatusCode: 200) == .operational)
        #expect(ProviderStatusPolicy.endpointStatus(forHTTPStatusCode: 204) == .operational)
        #expect(ProviderStatusPolicy.endpointStatus(forHTTPStatusCode: 401) == .unknown)
        #expect(ProviderStatusPolicy.endpointStatus(forHTTPStatusCode: 403) == .unknown)
        #expect(ProviderStatusPolicy.endpointStatus(forHTTPStatusCode: 405) == .unknown)
        #expect(ProviderStatusPolicy.endpointStatus(forHTTPStatusCode: 429) == .degraded)
        #expect(ProviderStatusPolicy.endpointStatus(forHTTPStatusCode: 500) == .down)
    }

    @Test func statuspageIndicatorsMapToStableStatuses() {
        #expect(ProviderStatusPolicy.statusPageStatus(indicator: "none") == .operational)
        #expect(ProviderStatusPolicy.statusPageStatus(indicator: "minor") == .degraded)
        #expect(ProviderStatusPolicy.statusPageStatus(indicator: "major") == .down)
        #expect(ProviderStatusPolicy.statusPageStatus(indicator: "critical") == .down)
        #expect(ProviderStatusPolicy.statusPageStatus(indicator: "maintenance") == .unknown)
    }
}
