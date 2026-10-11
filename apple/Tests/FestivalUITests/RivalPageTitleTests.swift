import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Rival page titles (issue #604, page-tools-and-nav-chrome R23)

/// Rival Detail's subtitle names the list it was opened from: one chart's list
/// ("Lead Rivals", song or leaderboard rivals alike, like Android and Windows), else
/// "Rivals".
@Test func rivalDetailSubtitleNamesTheSingleChartListElseRivals() {
    #expect(RivalDetailScreen.subtitle(for: .song(instruments: ["Solo_Guitar"])) == "Lead Rivals")
    #expect(RivalDetailScreen.subtitle(for: .leaderboard(instrument: "Solo_Bass", rankBy: .totalscore))
        == "Bass Rivals")
    #expect(RivalDetailScreen.subtitle(for: .song(instruments: ["Solo_Guitar", "Solo_Bass"])) == "Rivals")
    #expect(RivalDetailScreen.subtitle(for: .combo(token: "03", instruments: ["Solo_Guitar", "Solo_Bass"]))
        == "Rivals")
    #expect(RivalDetailScreen.subtitle(for: .combo(token: RivalCombo.proDrumsToken, instruments: ["Solo_Drums"]))
        == "Rivals")
    #expect(RivalDetailScreen.subtitle(for: nil) == "Rivals")
    #expect(RivalDetailScreen.subtitle(for: .song(instruments: ["Not_A_Real_Instrument"])) == "Rivals")
}

/// Only a single-chart subtitle is led by that chart's icon (the same rule as All
/// Rivals' title icon).
@Test func rivalDetailSubtitleIconOnlyForSingleChartScopes() {
    #expect(RivalDetailScreen.subtitleInstrument(for: .song(instruments: ["Solo_Guitar"])) == .lead)
    #expect(RivalDetailScreen.subtitleInstrument(for: .leaderboard(instrument: "Solo_Drums", rankBy: .totalscore))
        == .drums)
    #expect(RivalDetailScreen.subtitleInstrument(for: .song(instruments: ["Solo_Guitar", "Solo_Bass"])) == nil)
    #expect(RivalDetailScreen.subtitleInstrument(for: .combo(token: "03", instruments: ["Solo_Guitar"])) == nil)
    #expect(RivalDetailScreen.subtitleInstrument(for: nil) == nil)
}

/// Rivalry is titled by its section over the rival's name ("Rival" until known).
@Test func rivalryTitleIsTheSectionOverTheRival() {
    #expect(RivalryScreen.title(for: "closest_battles") == "Closest Battles")
    #expect(RivalryScreen.title(for: "dominating_them") == "Dominating Them")
    #expect(RivalryScreen.title(for: "unknown") == "Rivalry")
    #expect(RivalryScreen.subtitle(rivalName: "Fixture Rival Golf") == "Fixture Rival Golf")
    #expect(RivalryScreen.subtitle(rivalName: nil) == "Rival")
}
