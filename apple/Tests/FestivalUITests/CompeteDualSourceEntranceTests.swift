import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - Compete Duo reading order (#354)

/// The Rivals pane header follows the leaderboard cards on screen, so the two panes
/// stagger in one reading order (load-transition R5).
@Test func competeDuoRivalsHeaderFollowsTheLeaderboardCardsOnScreen() {
    #expect(CompeteDualSourceEntrance.leaderboardsHeader == 0)
    #expect(CompeteDualSourceEntrance.firstLeaderboardCard == 1)
    // Two cards side by side on the inner display: header 0, cards 1–2, Rivals 3.
    #expect(CompeteDualSourceEntrance.rivalsHeader(instrumentCount: 6, leaderboardColumns: 2) == 3)
    // Fewer instruments than columns: only the cards that exist precede it.
    #expect(CompeteDualSourceEntrance.rivalsHeader(instrumentCount: 1, leaderboardColumns: 2) == 2)
    // No instruments: the pane's message takes the cards' place.
    #expect(CompeteDualSourceEntrance.rivalsHeader(instrumentCount: 0, leaderboardColumns: 2) == 2)
    #expect(CompeteDualSourceEntrance.rivalsHeader(instrumentCount: 4, leaderboardColumns: 1) == 2)
}

/// The page measures the carousel's columns with the carousel's own spacing and margins.
@Test func carouselColumnsUseTheCarouselsOwnSpacing() {
    let width = CompeteDualSourceEntrance.minimumCardWidth
    #expect(CarouselPaging.columns(width: 669, minimumCardWidth: width) == 2)
    #expect(CarouselPaging.columns(width: 466, minimumCardWidth: width) == 1)
    #expect(
        CarouselPaging.columns(width: 1000, minimumCardWidth: width)
            == CarouselPaging.columns(
                width: 1000, minimumCardWidth: width, spacing: CarouselPaging.spacing, margin: CarouselPaging.margin
            )
    )
}

/// The Rivals pane derives the leaderboard columns from the regions' width on its first
/// build (#354 review): the inner display's 669 pt shows two cards, so the Rivals header
/// waits for both; an unknown width assumes the most a carousel shows, so the header
/// never shares an entrance with a leaderboard card.
@Test func competeDuoLeaderboardColumnsComeFromTheRegionWidth() {
    #expect(CompeteDualSourceEntrance.leaderboardColumns(regionWidth: 669) == 2)
    #expect(CompeteDualSourceEntrance.leaderboardColumns(regionWidth: 668.6) == 2)
    #expect(CompeteDualSourceEntrance.leaderboardColumns(regionWidth: 466) == 1)
    #expect(CompeteDualSourceEntrance.leaderboardColumns(regionWidth: nil) == CarouselPaging.maximumColumns)
    let header = CompeteDualSourceEntrance.rivalsHeader(
        instrumentCount: 2, leaderboardColumns: CompeteDualSourceEntrance.leaderboardColumns(regionWidth: 669)
    )
    #expect(header == 3)
}
