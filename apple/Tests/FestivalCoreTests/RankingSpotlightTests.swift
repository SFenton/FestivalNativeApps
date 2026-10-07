import Foundation
import Testing
@testable import FestivalCore

/// Build a minimal decoded row for placement tests; only `accountId` and the
/// metric-specific rank/rating fields used by `AccountRankingEntry` matter here.
private func fixtureEntry(accountId: String, rank: Int = 1) throws -> AccountRankingEntry {
    let data = Data("""
    {"accountId":"\(accountId)","displayName":"Fixture","songsPlayed":10,
     "totalChartedSongs":20,"coverage":0.5,"rawSkillRating":0.01,
     "adjustedSkillRating":0.01,"adjustedSkillRank":\(rank),"weightedRating":0.02,
     "weightedRank":\(rank),"fcRate":0.4,"fcRateRank":\(rank),"totalScore":1000,
     "totalScoreRank":\(rank),"maxScorePercent":0.9,"maxScorePercentRank":\(rank),
     "avgAccuracy":0.95,"fullComboCount":5,"avgStars":4.0,"bestRank":1,"avgRank":2.0}
    """.utf8)
    return try JSONDecoder().decode(AccountRankingEntry.self, from: data)
}

// MARK: - No selection

@Test func spotlightPlacementIsNoneWithoutSelection() throws {
    let top = try [fixtureEntry(accountId: "a"), fixtureEntry(accountId: "b")]
    #expect(
        RankingSpotlight.placement(selectedAccountId: nil, visibleEntries: top, source: .notLoaded) == .none
    )
    #expect(
        RankingSpotlight.placement(selectedAccountId: "  ", visibleEntries: top, source: .notLoaded) == .none
    )
}

// MARK: - Already visible ("in top 10")

@Test func spotlightPlacementIsInlineWhenAlreadyVisible() throws {
    let top = try [fixtureEntry(accountId: "Selected-ID"), fixtureEntry(accountId: "b")]
    // Case-insensitive, matching the wire's inconsistent account-id casing.
    #expect(
        RankingSpotlight.placement(
            selectedAccountId: "selected-id", visibleEntries: top, source: .notLoaded
        ) == .inline
    )
}

// MARK: - Not visible ("below")

@Test func spotlightPlacementIsPendingWhileTheOwnRankIsStillLoading() throws {
    let top = try [fixtureEntry(accountId: "a")]
    #expect(
        RankingSpotlight.placement(
            selectedAccountId: "someone-else", visibleEntries: top, source: .notLoaded
        ) == .pending
    )
}

@Test func spotlightPlacementIsFooterWhenRankedBelowTheVisibleRows() throws {
    let top = try [fixtureEntry(accountId: "a")]
    let own = try fixtureEntry(accountId: "someone-else", rank: 57)
    #expect(
        RankingSpotlight.placement(
            selectedAccountId: "someone-else", visibleEntries: top, source: .available(own)
        ) == .footer(own)
    )
}

@Test func spotlightPlacementFallsBackToPendingOnAMismatchedFetch() throws {
    let top = try [fixtureEntry(accountId: "a")]
    // A stale fetch for a previously selected account must never be shown as the
    // newly selected account's row.
    let stale = try fixtureEntry(accountId: "stale-account", rank: 3)
    #expect(
        RankingSpotlight.placement(
            selectedAccountId: "new-account", visibleEntries: top, source: .available(stale)
        ) == .pending
    )
}

// MARK: - Unranked

@Test func spotlightPlacementIsUnrankedWhenNotVisibleAndNotRanked() throws {
    let top = try [fixtureEntry(accountId: "a")]
    #expect(
        RankingSpotlight.placement(
            selectedAccountId: "never-ranked", visibleEntries: top, source: .unranked
        ) == .unranked
    )
}

// MARK: - Full board pinned footer (issue #318)

@Test func pinnedFooterIsNoneWithoutSelection() throws {
    let page = try [fixtureEntry(accountId: "a")]
    #expect(RankingSpotlight.pinnedFooter(selectedAccountId: nil, visibleEntries: page, source: .notLoaded) == .none)
    #expect(RankingSpotlight.pinnedFooter(selectedAccountId: " ", visibleEntries: page, source: .notLoaded) == .none)
}

@Test func pinnedFooterStaysWhenThePlayerIsOnThePage() throws {
    let onPage = try fixtureEntry(accountId: "Selected-ID", rank: 4)
    let own = try fixtureEntry(accountId: "selected-id", rank: 4)
    let page = try [fixtureEntry(accountId: "a"), onPage]
    // Never `.inline`: the board pins the row on the player's own page too.
    #expect(
        RankingSpotlight.pinnedFooter(selectedAccountId: "selected-id", visibleEntries: page, source: .available(own))
            == .footer(own)
    )
    // The page's row stands in until the per-account row arrives (or if it fails).
    #expect(
        RankingSpotlight.pinnedFooter(selectedAccountId: "selected-id", visibleEntries: page, source: .notLoaded)
            == .footer(onPage)
    )
    #expect(
        RankingSpotlight.pinnedFooter(selectedAccountId: "selected-id", visibleEntries: page, source: .unranked)
            == .footer(onPage)
    )
}

@Test func pinnedFooterOffThePageFollowsTheOwnRow() throws {
    let page = try [fixtureEntry(accountId: "a")]
    let own = try fixtureEntry(accountId: "far", rank: 57)
    let stale = try fixtureEntry(accountId: "stale", rank: 3)
    #expect(RankingSpotlight.pinnedFooter(selectedAccountId: "far", visibleEntries: page, source: .available(own)) == .footer(own))
    #expect(RankingSpotlight.pinnedFooter(selectedAccountId: "far", visibleEntries: page, source: .notLoaded) == .pending)
    #expect(RankingSpotlight.pinnedFooter(selectedAccountId: "far", visibleEntries: page, source: .unranked) == .unranked)
    #expect(RankingSpotlight.pinnedFooter(selectedAccountId: "far", visibleEntries: page, source: .available(stale)) == .pending)
}

// MARK: - Ordinal formatting

@Test func ordinalFormatsGroupedRanks() {
    #expect(RankingFormatting.ordinal(1) == "1st")
    #expect(RankingFormatting.ordinal(2) == "2nd")
    #expect(RankingFormatting.ordinal(3) == "3rd")
    #expect(RankingFormatting.ordinal(1234) == "1,234th")
}

// MARK: - Page-for-rank

@Test func pageForRankMatchesPageSizeBoundaries() {
    #expect(LeaderboardPaging.page(forRank: 1, pageSize: 25) == 1)
    #expect(LeaderboardPaging.page(forRank: 25, pageSize: 25) == 1)
    #expect(LeaderboardPaging.page(forRank: 26, pageSize: 25) == 2)
    #expect(LeaderboardPaging.page(forRank: 57, pageSize: 25) == 3)
    #expect(LeaderboardPaging.page(forRank: 0, pageSize: 25) == 1)
    #expect(LeaderboardPaging.page(forRank: -5, pageSize: 25) == 1)
    #expect(LeaderboardPaging.page(forRank: 10, pageSize: 0) == 1)
}
