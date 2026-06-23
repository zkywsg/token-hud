import CoreGraphics
import Testing
@testable import token_hudCore

@Suite("NotchExpandedLayoutPolicy")
struct NotchExpandedLayoutPolicyTests {
    @Test func adaptiveModeGrowsWithServiceCount() {
        let few = NotchExpandedLayoutPolicy.layout(
            mode: .adaptive,
            widgetCount: 4,
            serviceCount: 2,
            screenHeight: 900,
            menuBarHeight: 32
        )
        let many = NotchExpandedLayoutPolicy.layout(
            mode: .adaptive,
            widgetCount: 12,
            serviceCount: 6,
            screenHeight: 900,
            menuBarHeight: 32
        )

        #expect(many.bodyHeight > few.bodyHeight)
        #expect(few.contentScale == 1)
        #expect(many.contentScale == 1)
    }

    @Test func adaptiveModeCapsHeightAndEnablesScrolling() {
        let layout = NotchExpandedLayoutPolicy.layout(
            mode: .adaptive,
            widgetCount: 30,
            serviceCount: 18,
            screenHeight: 600,
            menuBarHeight: 32
        )

        #expect(layout.bodyHeight <= 600 * NotchExpandedLayoutPolicy.maxScreenHeightFraction)
        #expect(layout.allowsVerticalScrolling)
        #expect(layout.contentScale == 1)
    }

    @Test func adaptiveModeEstimatesModelCardsByRows() {
        let layout = NotchExpandedLayoutPolicy.layout(
            mode: .adaptive,
            widgetCount: 5,
            serviceCount: 3,
            screenHeight: 900,
            menuBarHeight: 32
        )

        #expect(layout.bodyHeight >= 180)
        #expect(layout.bodyHeight < 240)
        #expect(!layout.allowsVerticalScrolling)
        #expect(layout.contentScale == 1)
    }

    @Test func adaptiveModeAccountsForSevenWidgetGroupedCards() {
        let layout = NotchExpandedLayoutPolicy.layout(
            mode: .adaptive,
            widgetCount: 7,
            serviceCount: 3,
            screenHeight: 900,
            menuBarHeight: 32
        )

        #expect(layout.bodyHeight >= 260)
        #expect(!layout.allowsVerticalScrolling)
        #expect(layout.contentScale == 1)
    }

    @Test func sectionedModeUsesMediumHeightRegardlessOfServiceCount() {
        let few = NotchExpandedLayoutPolicy.layout(
            mode: .sectioned,
            widgetCount: 4,
            serviceCount: 2,
            screenHeight: 900,
            menuBarHeight: 32
        )
        let many = NotchExpandedLayoutPolicy.layout(
            mode: .sectioned,
            widgetCount: 24,
            serviceCount: 12,
            screenHeight: 900,
            menuBarHeight: 32
        )

        #expect(few.bodyHeight == NotchExpandedLayoutPolicy.sectionedBodyHeight)
        #expect(many.bodyHeight == NotchExpandedLayoutPolicy.sectionedBodyHeight)
        #expect(many.allowsVerticalScrolling)
        #expect(many.contentScale == 1)
    }

    @Test func storedModeDefaultsToAdaptiveForUnknownValues() {
        #expect(NotchExpandedLayoutMode(rawStorageValue: "adaptive") == .adaptive)
        #expect(NotchExpandedLayoutMode(rawStorageValue: "sectioned") == .sectioned)
        #expect(NotchExpandedLayoutMode(rawStorageValue: "old-value") == .adaptive)
        #expect(NotchExpandedLayoutMode(rawStorageValue: "") == .adaptive)
    }
}
