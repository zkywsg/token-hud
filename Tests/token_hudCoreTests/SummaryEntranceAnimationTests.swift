import Testing
@testable import token_hudCore

@Suite("Summary entrance animation")
struct SummaryEntranceAnimationTests {
    @Test("Hero enters before later rows")
    func heroEntersBeforeLaterRows() {
        let hero = SummaryEntranceAnimation.progress(expansion: 0.7, rowIndex: 0, reduceMotion: false)
        let laterRow = SummaryEntranceAnimation.progress(expansion: 0.7, rowIndex: 4, reduceMotion: false)

        #expect(hero > laterRow)
    }

    @Test("All rows finish when fully expanded")
    func allRowsFinishWhenFullyExpanded() {
        for rowIndex in 0..<20 {
            #expect(SummaryEntranceAnimation.progress(
                expansion: 1,
                rowIndex: rowIndex,
                reduceMotion: false
            ) == 1)
        }
    }

    @Test("Long list stagger is capped at row six")
    func longListStaggerIsCapped() {
        let cappedRow = SummaryEntranceAnimation.progress(expansion: 0.8, rowIndex: 6, reduceMotion: false)
        let laterRow = SummaryEntranceAnimation.progress(expansion: 0.8, rowIndex: 19, reduceMotion: false)

        #expect(cappedRow == laterRow)
    }

    @Test("Reduce Motion removes row stagger")
    func reduceMotionRemovesRowStagger() {
        let hero = SummaryEntranceAnimation.progress(expansion: 0.7, rowIndex: 0, reduceMotion: true)
        let laterRow = SummaryEntranceAnimation.progress(expansion: 0.7, rowIndex: 19, reduceMotion: true)

        #expect(hero == laterRow)
    }
}
