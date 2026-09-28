import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Player graphs cards

/// Each played instrument contributes Rank History, then Percentiles when placed;
/// unplayed instruments contribute nothing.
@Test func playerChartsCardsPerPlayedInstrument() {
    let bucket = PlayerPercentileBucket(topPercent: 1, count: 3)
    let cards = PlayerChartsCarousel.cards(
        instruments: [.lead, .bass, .drums],
        songsPlayed: { $0 == .bass ? 0 : 5 },
        buckets: { $0 == .lead ? [bucket] : [] }
    )
    #expect(cards == [.rankHistory(.lead), .percentiles(.lead, [bucket]), .rankHistory(.drums)])
}

// MARK: - Song history cards

/// Song Detail's history region shows only visible charts the player has scored,
/// in display order (no request for an unscored chart).
@Test func songHistoryCardsOnlyScoredVisibleCharts() {
    #expect(SongHistoryCarouselPane.instruments(visible: [.lead, .bass, .drums], scored: [.drums, .lead, .vocals])
        == [.lead, .drums])
    #expect(SongHistoryCarouselPane.instruments(visible: [.lead], scored: []).isEmpty)
}
