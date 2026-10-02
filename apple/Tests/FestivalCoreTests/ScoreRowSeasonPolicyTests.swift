import Foundation
import Testing
@testable import FestivalCore

@Test func historyListShowsSeasonOnlyFromTheWebBreakpoint() {
    // Portrait iPhones (320–440 pt) hide it, like the web below 520 px.
    for width in [0.0, 320, 393, 440, 519.5] {
        #expect(!ScoreRowSeasonPolicy.showsSeason(.historyList, width: width, season: 9))
        #expect(!ScoreRowSeasonPolicy.showsColumn(.historyList, width: width))
    }
    for width in [520.0, 874, 1_024] {
        #expect(ScoreRowSeasonPolicy.showsSeason(.historyList, width: width, season: 9))
        #expect(ScoreRowSeasonPolicy.showsColumn(.historyList, width: width))
    }
}

@Test func topScoresUseTheSameBreakpointAgainstTheCardWidth() {
    #expect(!ScoreRowSeasonPolicy.showsSeason(.topScores, width: 361, season: 3))
    #expect(!ScoreRowSeasonPolicy.showsSeason(.topScores, width: 519, season: 3))
    #expect(ScoreRowSeasonPolicy.showsSeason(.topScores, width: 520, season: 3))
    #expect(ScoreRowSeasonPolicy.breakpoint == 520)
}

@Test func historyDetailAlwaysShowsAKnownSeason() {
    #expect(ScoreRowSeasonPolicy.showsSeason(.historyDetail, width: 0, season: 1))
    #expect(ScoreRowSeasonPolicy.showsColumn(.historyDetail, width: 0))
    #expect(!ScoreRowSeasonPolicy.showsSeason(.historyDetail, width: 900, season: nil))
}

@Test func missingInvalidOrUnmeasuredSeasonsAreHidden() {
    #expect(!ScoreRowSeasonPolicy.showsSeason(.historyList, width: 900, season: nil))
    #expect(!ScoreRowSeasonPolicy.showsSeason(.topScores, width: 900, season: 0))
    #expect(!ScoreRowSeasonPolicy.showsSeason(.topScores, width: 900, season: -2))
    #expect(!ScoreRowSeasonPolicy.showsSeason(.historyList, width: .infinity, season: 4))
    #expect(!ScoreRowSeasonPolicy.showsSeason(.topScores, width: .nan, season: 4))
}
