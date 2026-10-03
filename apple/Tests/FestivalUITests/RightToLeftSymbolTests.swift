import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Right-to-left navigation glyphs

/// Pager steps use the reading-direction symbols, so First/Previous point right and
/// Next/Last point left in an RTL layout. HIG Right to left: "next and previous buttons
/// each flip to match RTL reading order" (`/duo` Stage 5 RTL check, 2026-10-02).
@Test func rankingsPagerSymbolsFollowReadingDirection() {
    #expect(RankingsGlassPager.symbol(.first) == "chevron.backward.2")
    #expect(RankingsGlassPager.symbol(.previous) == "chevron.backward")
    #expect(RankingsGlassPager.symbol(.next) == "chevron.forward")
    #expect(RankingsGlassPager.symbol(.last) == "chevron.forward.2")
}
