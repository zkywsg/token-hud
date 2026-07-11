import Testing
@testable import token_hudCore

@Suite("Summary entrance animation")
struct SummaryEntranceAnimationTests {
    @Test("Progress uses the configured content start and stagger step")
    func progressUsesConfiguredTiming() {
        let hero = SummaryEntranceAnimation.progress(expansion: 0.79, rowIndex: 0, reduceMotion: false)
        let firstRow = SummaryEntranceAnimation.progress(expansion: 0.79, rowIndex: 1, reduceMotion: false)
        let expectedFirstRow = (0.79 - 0.605) / (1 - 0.605)

        #expect(abs(hero - 0.5) < 0.000_001)
        #expect(abs(firstRow - expectedFirstRow) < 0.000_001)
    }

    @Test("Expansion and negative row indices are clamped")
    func inputsAreClamped() {
        #expect(SummaryEntranceAnimation.progress(expansion: -0.1, rowIndex: 0, reduceMotion: false) == 0)
        #expect(SummaryEntranceAnimation.progress(expansion: 1.1, rowIndex: 0, reduceMotion: false) == 1)

        let negativeRow = SummaryEntranceAnimation.progress(expansion: 0.79, rowIndex: -1, reduceMotion: false)
        let hero = SummaryEntranceAnimation.progress(expansion: 0.79, rowIndex: 0, reduceMotion: false)
        #expect(negativeRow == hero)
    }

    @Test("Non-finite expansion has deterministic bounds")
    func nonFiniteExpansionHasDeterministicBounds() {
        #expect(SummaryEntranceAnimation.progress(expansion: .nan, rowIndex: 0, reduceMotion: false) == 0)
        #expect(SummaryEntranceAnimation.progress(expansion: -.infinity, rowIndex: 0, reduceMotion: false) == 0)
        #expect(SummaryEntranceAnimation.progress(expansion: .infinity, rowIndex: 0, reduceMotion: false) == 1)
    }

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
