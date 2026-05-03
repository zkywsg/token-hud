import CoreGraphics
import Testing
@testable import token_hudCore

@Suite("PanelResizeCalculator")
struct PanelResizeCalculatorTests {

    @Test func bottomRightDragExpandsWhileKeepingTopLeftAnchored() {
        let initial = CGRect(x: 100, y: 100, width: 300, height: 60)

        let resized = PanelResizeCalculator.bottomRightFrame(
            from: initial,
            dragDelta: CGSize(width: 40, height: -20),
            minSize: CGSize(width: 120, height: 40)
        )

        #expect(resized.origin.x == 100)
        #expect(resized.origin.y == 80)
        #expect(resized.width == 340)
        #expect(resized.height == 80)
        #expect(resized.maxY == initial.maxY)
    }

    @Test func bottomRightDragClampsToMinimumSize() {
        let initial = CGRect(x: 100, y: 100, width: 300, height: 60)

        let resized = PanelResizeCalculator.bottomRightFrame(
            from: initial,
            dragDelta: CGSize(width: -500, height: 500),
            minSize: CGSize(width: 120, height: 40)
        )

        #expect(resized.origin.x == 100)
        #expect(resized.origin.y == 120)
        #expect(resized.width == 120)
        #expect(resized.height == 40)
        #expect(resized.maxY == initial.maxY)
    }
}
