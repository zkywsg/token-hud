import Testing
@testable import token_hudCore

@Suite("Service accent colors")
struct ServiceAccentColorTests {

    private static let knownServices = [
        "claude", "openai", "codex", "gemini",
        "deepseek", "anthropic", "minimax", "mimo",
    ]

    @Test func knownServicesResolveToDistinctColors() {
        let colors = Self.knownServices.map { serviceAccentColor(for: $0) }
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                #expect(colors[i] != colors[j])
            }
        }
    }

    @Test func lookupIsCaseInsensitive() {
        #expect(serviceAccentColor(for: "Claude") == serviceAccentColor(for: "claude"))
        #expect(serviceAccentColor(for: "CODEX") == serviceAccentColor(for: "codex"))
    }

    @Test func unknownServiceFallsBackToNeutralGray() {
        let fallback = serviceAccentColor(for: "some-future-tool")
        #expect(fallback == ServiceAccentColor(red: 0.60, green: 0.60, blue: 0.63))
    }

    @Test func fallbackColorIsNotUsedByAnyKnownService() {
        let fallback = serviceAccentColor(for: "unknown")
        for service in Self.knownServices {
            #expect(serviceAccentColor(for: service) != fallback)
        }
    }
}
