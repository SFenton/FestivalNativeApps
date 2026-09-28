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
