import Testing
@testable import token_hudCore

@Suite("Summary entrance animation")
struct SummaryEntranceAnimationTests {
    @Test("Rows use a 25 millisecond stagger capped at row six")
    func rowsUseCappedDelay() {
        #expect(abs(SummaryEntranceAnimation.delay(rowIndex: 0, reduceMotion: false) - 0) < 0.000_001)
        #expect(abs(SummaryEntranceAnimation.delay(rowIndex: 1, reduceMotion: false) - 0.025) < 0.000_001)
        #expect(abs(SummaryEntranceAnimation.delay(rowIndex: 6, reduceMotion: false) - 0.15) < 0.000_001)
        #expect(abs(SummaryEntranceAnimation.delay(rowIndex: 100, reduceMotion: false) - 0.15) < 0.000_001)
    }

    @Test("Negative row indices have no delay")
    func negativeRowHasNoDelay() {
        #expect(SummaryEntranceAnimation.delay(rowIndex: -1, reduceMotion: false) == 0)
    }

    @Test("Reduce Motion removes delay for every row")
    func reduceMotionRemovesDelay() {
        for rowIndex in [-1, 0, 1, 6, 100] {
            #expect(SummaryEntranceAnimation.delay(rowIndex: rowIndex, reduceMotion: true) == 0)
        }
    }

    @Test("Only an explicit collapsed to expanded edge animates")
    func onlyExpansionEdgeAnimates() {
        #expect(SummaryEntranceAnimation.shouldAnimate(previous: false, current: true))
        #expect(!SummaryEntranceAnimation.shouldAnimate(previous: nil, current: true))
        #expect(!SummaryEntranceAnimation.shouldAnimate(previous: true, current: true))
        #expect(!SummaryEntranceAnimation.shouldAnimate(previous: true, current: false))
        #expect(!SummaryEntranceAnimation.shouldAnimate(previous: false, current: false))
        #expect(!SummaryEntranceAnimation.shouldAnimate(previous: nil, current: nil))
    }
}
