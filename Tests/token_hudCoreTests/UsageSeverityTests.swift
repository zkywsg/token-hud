// Tests/token_hudCoreTests/UsageSeverityTests.swift
import Testing
@testable import token_hudCore

@Suite("Usage severity")
struct UsageSeverityTests {
    @Test("Low usage is ok")
    func lowUsageIsOk() {
        #expect(UsageSeverity.forFraction(0) == .ok)
        #expect(UsageSeverity.forFraction(0.4) == .ok)
        #expect(UsageSeverity.forFraction(0.649) == .ok)
    }

    @Test("Mid usage warns")
    func midUsageWarns() {
        #expect(UsageSeverity.forFraction(0.65) == .warn)
        #expect(UsageSeverity.forFraction(0.8) == .warn)
        #expect(UsageSeverity.forFraction(0.849) == .warn)
    }

    @Test("High usage is critical")
    func highUsageIsCritical() {
        #expect(UsageSeverity.forFraction(0.85) == .critical)
        #expect(UsageSeverity.forFraction(0.99) == .critical)
    }

    @Test("Out-of-range fractions are clamped")
    func clampsOutOfRange() {
        #expect(UsageSeverity.forFraction(-0.5) == .ok)
        #expect(UsageSeverity.forFraction(1.5) == .critical)
    }
}
