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
