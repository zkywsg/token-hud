import Testing
@testable import token_hudCore

@Suite("FloatingPanelContentLayoutPolicy")
struct FloatingPanelContentLayoutPolicyTests {

    @Test func detachedFloatingPanelContentUsesTopAnchors() {
        let layout = FloatingPanelContentLayoutPolicy.layout()

        #expect(layout.verticalPlacement == .top)
        #expect(layout.scaleAnchor == .top)
    }

    @Test func groupedModelCardsUseCardRowsForAdaptiveScale() {
        let compactScale = FloatingPanelContentLayoutPolicy.adaptiveScale(
            panelHeight: 220,
            overlayMode: "compact",
            serviceCount: 3
        )
        let groupedScale = FloatingPanelContentLayoutPolicy.adaptiveScale(
            panelHeight: 220,
            overlayMode: "grouped",
            serviceCount: 3
        )

        #expect(compactScale > groupedScale)
        #expect(groupedScale <= 1.35)
        #expect(groupedScale >= 0.72)
    }
}
