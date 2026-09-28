import Foundation
import Testing
@testable import FestivalCore

// MARK: - Pager state

@Test func pagerStateClampsPageAndTotal() {
    #expect(RankingsPagerState(page: 0, totalPages: 0) == RankingsPagerState(page: 1, totalPages: 1))
    #expect(RankingsPagerState(page: 9, totalPages: 4).page == 4)
    #expect(RankingsPagerState(page: -3, totalPages: 4).page == 1)
}

@Test func pagerFirstPageDisablesBackActions() {
    let state = RankingsPagerState(page: 1, totalPages: 34_757)
    #expect(!state.canGoBack)
    #expect(state.canGoForward)
    #expect(state.destination(for: .first) == nil)
    #expect(state.destination(for: .previous) == nil)
    #expect(state.destination(for: .next) == 2)
    #expect(state.destination(for: .last) == 34_757)
}

@Test func pagerLastPageDisablesForwardActions() {
    let state = RankingsPagerState(page: 48, totalPages: 48)
    #expect(state.destination(for: .first) == 1)
    #expect(state.destination(for: .previous) == 47)
    #expect(state.destination(for: .next) == nil)
    #expect(state.destination(for: .last) == nil)
}

@Test func pagerSinglePageDisablesEverything() {
    let state = RankingsPagerState(page: 1, totalPages: 1)
    for action in RankingsPagerAction.allCases {
        #expect(state.destination(for: action) == nil)
    }
}

@Test func pagerLabelsGroupDigits() {
    let state = RankingsPagerState(page: 1_234, totalPages: 34_757)
    let page = 1_234.formatted(.number.grouping(.automatic))
    let total = 34_757.formatted(.number.grouping(.automatic))
    #expect(state.label == "\(page) / \(total)")
    #expect(state.accessibilityValue == "\(page) of \(total)")
}

@Test func pagerActionsKeepVisibleOrderAndIdentifiers() {
    #expect(RankingsPagerAction.allCases.map(\.rawValue) == ["first", "previous", "next", "last"])
}

// MARK: - Count labels

@Test func viewAllLabelsIncludeCountOnlyWhenPositive() {
    let count = 868_901.formatted(.number.grouping(.automatic))
    #expect(RankingsCountText.viewAllRankings(totalAccounts: 868_901) == "View all rankings (\(count))")
    #expect(RankingsCountText.viewAllRankings(totalAccounts: 0) == "View all rankings")
    #expect(RankingsCountText.viewAllBandRankings(totalTeams: 3) == "View all band rankings (3)")
    #expect(RankingsCountText.viewAllBandRankings(totalTeams: 0) == "View all band rankings")
}

@Test func rankedCountSubtitlesPluralize() {
    #expect(RankingsCountText.rankedPlayers(1) == "1 ranked player")
    #expect(RankingsCountText.rankedPlayers(3) == "3 ranked players")
    #expect(RankingsCountText.rankedBands(1) == "1 ranked band")
    #expect(RankingsCountText.rankedBands(600).hasSuffix(" ranked bands"))
}

@Test func spokenSongsReadsFraction() {
    #expect(RankingsCountText.spokenSongs("728 / 729") == "728 of 729 songs")
    #expect(RankingsCountText.spokenSongs("20 / 50", fullCombos: true) == "20 full combos of 50 songs")
    #expect(RankingsCountText.spokenSongs("odd") == "odd")
}
