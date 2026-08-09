// Tests/token_hudCoreTests/FocusGaugeStyleTests.swift
import Testing
@testable import token_hudCore

@Suite("Focus gauge style")
struct FocusGaugeStyleTests {
    @Test("Known raw values round-trip")
    func knownValuesRoundTrip() {
        for style in FocusGaugeStyle.allCases {
            #expect(FocusGaugeStyle.from(style.rawValue) == style)
        }
    }

    @Test("Unknown raw value falls back to the default")
    func unknownFallsBack() {
        #expect(FocusGaugeStyle.from("") == .default)
        #expect(FocusGaugeStyle.from("classicBars") == .default)
        #expect(FocusGaugeStyle.from("nope") == .default)
    }

    @Test("All eight styles are offered and uniquely named")
    func allStylesPresent() {
        #expect(FocusGaugeStyle.allCases.count == 8)
        let names = Set(FocusGaugeStyle.allCases.map(\.displayName))
        #expect(names.count == 8)
        #expect(!names.contains(""))
    }
}
