import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - All Rivals title (issue #557)

/// Every scope keeps its page name (navigation title, Back menus, the Mac window).
@Test func allRivalsTitleNamesEveryScope() {
    #expect(AllRivalsScreen.title(for: .song(instruments: ["Solo_Guitar"])) == "Lead Rivals")
    #expect(AllRivalsScreen.title(for: .leaderboard(instrument: "Solo_Bass", rankBy: .totalscore))
        == "Bass Leaderboard Rivals")
    #expect(AllRivalsScreen.title(for: .song(instruments: ["Solo_Guitar", "Solo_Bass"])) == "Common Rivals")
    #expect(AllRivalsScreen.title(for: .combo(token: "03", instruments: ["Solo_Guitar", "Solo_Bass"]))
        == "Combo Rivals")
    #expect(AllRivalsScreen.title(for: .combo(token: RivalCombo.proDrumsToken, instruments: []))
        == "Pro Drums Family Rivals")
}

/// Only a single-instrument list leads its title with the instrument icon; Common and
/// Combo lists have none, like the web `AllRivalsPage`.
@Test func allRivalsTitleIconOnlyForSingleInstrumentScopes() {
    #expect(AllRivalsScreen.titleInstrument(for: .song(instruments: ["Solo_Guitar"])) == .lead)
    #expect(AllRivalsScreen.titleInstrument(for: .leaderboard(instrument: "Solo_Drums", rankBy: .totalscore))
        == .drums)
    #expect(AllRivalsScreen.titleInstrument(for: .song(instruments: ["Solo_Guitar", "Solo_Bass"])) == nil)
    #expect(AllRivalsScreen.titleInstrument(for: .combo(token: "03", instruments: ["Solo_Guitar", "Solo_Bass"]))
        == nil)
    #expect(AllRivalsScreen.titleInstrument(for: .combo(token: RivalCombo.proDrumsToken, instruments: ["Solo_Drums"]))
        == nil)
    #expect(AllRivalsScreen.titleInstrument(for: .song(instruments: ["Not_A_Real_Instrument"])) == nil)
}
