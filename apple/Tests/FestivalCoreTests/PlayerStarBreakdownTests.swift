import Foundation
import Testing
@testable import FestivalCore

/// Web `computeInstrumentStats` star counts and `formatClamped2` average.
@Test func starBreakdownCountsEveryTierAndAveragesStarredScores() throws {
    let profile = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-stars","totalScores":7,"scores":[
      {"si":"a","ins":"01","sc":1,"st":6},{"si":"b","ins":"01","sc":1,"st":5},
      {"si":"c","ins":"01","sc":1,"st":4},{"si":"d","ins":"01","sc":1,"st":3},
      {"si":"e","ins":"01","sc":1,"st":2},{"si":"f","ins":"01","sc":1},
      {"si":"a","ins":"02","sc":1,"st":6}]}
    """.utf8))
    let lead = profile.starBreakdown(.lead)
    #expect(lead.gold == 1 && lead.five == 1 && lead.four == 1)
    #expect(lead.three == 1 && lead.two == 1 && lead.one == 0)
    #expect(lead.average == 4, "Unstarred scores are excluded from the mean")
    #expect(lead.averageText == "4")
    #expect(!lead.isAllGold)
    #expect(lead.countCards.map(\.label) == ["Gold Stars", "5 Stars", "4 Stars", "3 Stars", "2 Stars"])

    let bass = profile.starBreakdown(.bass)
    #expect(bass.isAllGold && bass.countCards.map(\.stars) == [6])
    let empty = profile.starBreakdown(.drums)
    #expect(empty.average == 0 && empty.averageText == "\u{2014}" && empty.countCards.isEmpty)
}

@Test func averageStarsTextTrimsTrailingZerosLikeTheWeb() {
    func text(_ average: Double) -> String {
        PlayerStarBreakdown(gold: 0, five: 0, four: 0, three: 0, two: 0, one: 0, average: average).averageText
    }
    #expect(text(5.5) == "5.5")
    #expect(text(5.25) == "5.25")
    #expect(text(4.333) == "4.33")
    #expect(text(5.999) == "6")
}
