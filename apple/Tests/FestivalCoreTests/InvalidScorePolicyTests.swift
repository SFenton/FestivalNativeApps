import Foundation
import Testing
@testable import FestivalCore

/// One catalogue song with CHOpt maxima and a Lead population curve.
///
/// - Returns: A validated local song.
/// - Throws: Invalid locally authored catalogue.
private func invalidScoreSong() throws -> Song {
    let songs = try JSONDecoder().decode(SongsResponse.self, from: Data("""
    {"count":1,"songs":[
      {"songId":"pulse","title":"Pulse","artist":"Fixture",
       "difficulty":{"guitar":4,"bass":3,"drums":3,"vocals":2},
       "maxScores":{"Solo_Guitar":100000,"Solo_Bass":100000,"Solo_Drums":100000,
                    "Solo_Vocals":100000},
       "populationTiers":{
         "Solo_Guitar":{"bc":20,"t":[{"l":0.5,"t":22},{"l":2,"t":25}]},
         "Solo_Bass":{"bc":-1,"t":[]},
         "Solo_Drums":"corrupt"}}
    ]}
    """.utf8))
    try songs.validate()
    return try #require(songs.songs.first)
}

/// Decode compact selected-player scores through the real wire model.
///
/// - Parameter scores: Comma-separated compact score objects.
/// - Returns: The song's scores by chart.
/// - Throws: Invalid locally authored profile.
private func scores(_ scores: String) throws -> [Instrument: PlayerScore] {
    let player = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-invalid","totalScores":4,"scores":[\(scores)]}
    """.utf8))
    return try player.scoreIndex(requestedAccountId: "fixture-invalid")["pulse"] ?? [:]
}

@Test func populationTiersDecodeLenientlyAndPickTheLastTierAtTheLeeway() throws {
    let song = try invalidScoreSong()
    let lead = try #require(song.populationTiers?.tiers(for: .lead))
    #expect(lead.total(atLeeway: 0) == 20)
    #expect(lead.total(atLeeway: 0.5) == 22)
    #expect(lead.total(atLeeway: 1.9) == 22)
    #expect(lead.total(atLeeway: 5) == 25)
    #expect(song.populationTiers?.tiers(for: .bass) == nil)
    #expect(song.populationTiers?.tiers(for: .drums) == nil)
    #expect(InvalidScorePolicy.rank(in: nil, leeway: 1) == nil)
}

@Test func thresholdIsUnroundedAndInertWithoutAMaximum() {
    #expect(!InvalidScorePolicy.exceedsThreshold(score: 101_000, maxScore: 100_000, leeway: 1))
    #expect(InvalidScorePolicy.exceedsThreshold(score: 101_001, maxScore: 100_000, leeway: 1))
    #expect(!InvalidScorePolicy.exceedsThreshold(score: 900_000, maxScore: nil, leeway: 1))
    #expect(!InvalidScorePolicy.exceedsThreshold(score: 900_000, maxScore: 0, leeway: 1))
}

/// Web `SongsPage.effectiveScores`: valid raw, variant fallback, no fallback, legacy
/// fallback and over-threshold outcomes for one song.
@Test func songsEffectiveScoresMatchTheWebSubstitution() throws {
    let song = try invalidScoreSong()
    let raw = try scores("""
    {"si":"pulse","ins":"04","sc":99000,"fc":false,"st":5,"rk":3,"te":30,"ml":0},
    {"si":"pulse","ins":"01","sc":120000,"acc":990,"fc":false,"st":6,"rk":1,"te":30,"ml":3,
     "vs":[{"sc":99500,"acc":970,"fc":true,"ml":0.5,"rt":[{"l":0.5,"r":9},{"l":1,"r":5}]},
           {"sc":95000,"ml":0}]},
    {"si":"pulse","ins":"02","sc":130000,"rk":1,"te":30,"ml":4,"vs":[{"sc":120000,"ml":3}]},
    {"si":"pulse","ins":"08","sc":150000,"acc":999,"fc":false,"st":6,"rk":1,"te":30,
     "validScore":98000,"validAccuracy":960,"validIsFullCombo":true,"validRank":7,
     "validStars":5,"validTotalEntries":28}
    """)

    let result = InvalidScorePolicy.resolve(raw, song: song, leeway: 1)
    #expect(result.scores[.lead]?.score == 99_500)
    #expect(result.scores[.lead]?.isFullCombo == true)
    #expect(result.scores[.lead]?.accuracy == 970_000)
    #expect(result.scores[.lead]?.stars == 6)
    #expect(result.scores[.lead]?.rank == 5)
    #expect(result.scores[.lead]?.totalEntries == 22)
    #expect(result.scores[.lead]?.percentile == nil)
    #expect(result.scores[.bass] == nil)
    #expect(result.scores[.vocals]?.score == 98_000)
    #expect(result.scores[.vocals]?.rank == 7)
    #expect(result.scores[.vocals]?.stars == 5)
    #expect(result.scores[.vocals]?.totalEntries == 28)
    #expect(result.scores[.vocals]?.isFullCombo == true)
    #expect(result.scores[.drums] == raw[.drums])
    #expect(result.reasons == [.lead: .fallback, .bass: .noFallback, .vocals: .fallback])

    let lower = InvalidScorePolicy.resolve(raw, song: song, leeway: 0.2)
    #expect(lower.scores[.lead]?.score == 95_000)
    #expect(lower.scores[.lead]?.rank == 1)
    #expect(lower.scores[.lead]?.totalEntries == 20)

    let over = InvalidScorePolicy.resolve(raw, song: song, leeway: 1, overThreshold: [.lead, .drums])
    #expect(over.scores[.lead] == raw[.lead])
    #expect(over.reasons[.lead] == .overThreshold)
    #expect(over.reasons[.drums] == nil)

    let generous = InvalidScorePolicy.resolve(raw, song: song, leeway: 5)
    #expect(generous.scores[.lead] == raw[.lead])
    #expect(generous.scores[.bass] == raw[.bass])
    #expect(generous.reasons == [.vocals: .fallback])

    let index = InvalidScorePolicy.resolve(
        index: ["pulse": [.bass: try #require(raw[.bass])]], songsById: ["pulse": song], leeway: 1
    )
    #expect(index.isEmpty)
}

/// Web `filterPlayerScores` (Song Detail): a precomputed `minLeeway` never falls back
/// to the legacy fields, and a raw score without one uses the ceiling.
@Test func songDetailFilteringMatchesFilterPlayerScores() throws {
    let song = try invalidScoreSong()
    let raw = try scores("""
    {"si":"pulse","ins":"02","sc":120000,"rk":1,"te":30,"ml":2,"validScore":90000},
    {"si":"pulse","ins":"01","sc":120000,"rk":1,"te":30,"ml":2,
     "vs":[{"sc":99000,"ml":0,"rt":[{"l":0,"r":4}]}]},
    {"si":"pulse","ins":"08","sc":150000,"rk":1,"te":30,"validScore":98000},
    {"si":"pulse","ins":"04","sc":100500,"rk":2,"te":30}
    """)
    let filtered = InvalidScorePolicy.filtered(raw, song: song, leeway: 1)
    #expect(filtered[.lead]?.score == 99_000)
    #expect(filtered[.lead]?.rank == 4)
    #expect(filtered[.lead]?.totalEntries == 22)
    #expect(filtered[.bass] == nil)
    #expect(filtered[.vocals]?.score == 98_000)
    #expect(filtered[.vocals]?.rank == 0)
    #expect(filtered[.drums] == raw[.drums])
    #expect(InvalidScorePolicy.filtered(raw, song: song, leeway: nil) == raw)
}

/// Web `PlayerContent` `effectiveScores` (`invalid-scores` R9, #619): any viewed
/// player's profile aggregates its Song Details scores, so a substituted score brings
/// its filtered rank and population into Best Rank and the percentiles, a dropped score
/// leaves the profile, and the filter off (or a wide leeway) gives back the raw figures.
@Test func playerProfileFiguresUseEffectiveScoresAtTheLeeway() throws {
    let song = try invalidScoreSong()
    let raw = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-viewed","totalScores":5,"scores":[
     {"si":"pulse","ins":"01","sc":99000,"st":6,"fc":true,"acc":1000,"rk":1,"te":30,"ml":2,
      "vs":[{"sc":95000,"st":5,"fc":false,"acc":950,"ml":0.5,"rt":[{"l":0.5,"r":4}]}]},
     {"si":"pulse","ins":"02","sc":99000,"st":5,"rk":2,"te":30,"ml":3,
      "vs":[{"sc":90000,"ml":2.5,"rt":[{"l":2.5,"r":8}]}]},
     {"si":"pulse","ins":"04","sc":102000,"st":5,"rk":1,"te":30,
      "validScore":98000,"validRank":9,"validTotalEntries":40},
     {"si":"pulse","ins":"08","sc":101500,"st":5,"rk":1,"te":30},
     {"si":"uncatalogued","ins":"01","sc":999999,"st":4,"rk":7,"te":10}]}
    """.utf8))
    #expect(try raw.validate(requestedAccountId: "fixture-viewed") == .available)
    let songs = ["pulse": song]

    let off = raw.filteringInvalidScores(songsById: songs, leeway: nil)
    #expect(off == raw)
    #expect(off.overallStats(visibleInstruments: Set(Instrument.allCases)).bestRank == 1)

    let on = raw.filteringInvalidScores(songsById: songs, leeway: 1)
    #expect(on.accountId == raw.accountId && on.totalScores == on.scores.count)
    #expect(on.scores.count == 3)
    let overall = on.overallStats(visibleInstruments: Set(Instrument.allCases))
    #expect(overall.bestRank == 4)
    #expect(overall.bestRankSongId == "pulse")
    #expect(overall.bestRankInstrument == .lead)
    #expect(overall.goldStarCount == 0)
    let lead = on.instrumentStats(.lead)
    #expect(lead.songsPlayed == 2 && lead.bestRank == 4 && lead.bestRankSongId == "pulse")
    #expect(lead.fullComboCount == 0)
    #expect(on.instrumentStats(.bass).songsPlayed == 0)
    #expect(on.instrumentStats(.vocals).songsPlayed == 0)
    #expect(on.instrumentStats(.drums).bestRank == 9)
    #expect(on.starBreakdown(.lead).gold == 0 && on.starBreakdown(.lead).five == 1)
    // 4 of 22 (the Lead population at 1%) is the top 20%; 7 of 10 the top 70%.
    #expect(on.percentileBuckets(.lead) == [
        PlayerPercentileBucket(topPercent: 20, count: 1), PlayerPercentileBucket(topPercent: 70, count: 1),
    ])
    #expect(raw.percentileBuckets(.lead) == [
        PlayerPercentileBucket(topPercent: 4, count: 1), PlayerPercentileBucket(topPercent: 70, count: 1),
    ])
    #expect(on.percentileBuckets(.drums) == [PlayerPercentileBucket(topPercent: 25, count: 1)])

    // The same scores Song Details shows for the selected player (R4), so a selected
    // and a viewed profile agree.
    let index = try raw.scoreIndex(requestedAccountId: "fixture-viewed")
    let detail = InvalidScorePolicy.filtered(index["pulse"] ?? [:], song: song, leeway: 1)
    #expect(Set(on.scores.filter { $0.songId == "pulse" }.map(\.instrument)) == Set(detail.keys))
    for score in on.scores where score.songId == "pulse" {
        #expect(detail[score.instrument] == score)
    }

    // At a 3% leeway every raw score is valid again: the page shows the raw figures.
    let wide = raw.filteringInvalidScores(songsById: songs, leeway: 3)
    #expect(wide.scores == raw.scores)

    // Without the catalogue only `ml` decides: the drums and vocals scores stay raw.
    let noCatalogue = raw.filteringInvalidScores(songsById: [:], leeway: 1)
    #expect(noCatalogue.scores.map(\.instrument) == [.lead, .drums, .vocals, .lead])
    #expect(noCatalogue.scores.first?.totalEntries == 30)

    let payload = PlayerProfilePayload(profile: raw, state: .available, publicationId: 7, observedPublicationId: 7)
    #expect(payload.filteringInvalidScores(songsById: songs, leeway: nil).profile == raw)
    let filtered = payload.filteringInvalidScores(songsById: songs, leeway: 1)
    #expect(filtered.profile == on && filtered.publicationId == 7 && filtered.state == .available)
}

@Test func warningMessagesMatchTheWebStrings() {
    #expect(InvalidScoreWarning.make(
        songTitle: "Pulse", reasons: [:], instrumentFilter: nil, visibleInstruments: Set(Instrument.allCases)
    ) == nil)
    #expect(InvalidScoreWarning.make(
        songTitle: "Pulse", reasons: [.bass: .fallback], instrumentFilter: .lead,
        visibleInstruments: Set(Instrument.allCases)
    ) == nil)

    let one = InvalidScoreWarning.make(
        songTitle: "Pulse", reasons: [.lead: .fallback], instrumentFilter: .lead,
        visibleInstruments: Set(Instrument.allCases)
    )
    #expect(one?.isOverThreshold == false)
    #expect(one?.message == "Pulse has an invalid, filtered-out score on Lead. "
        + "We are showing the next valid score here.\n\n"
        + "To see the absolute highest score you've achieved, toggle off 'Filter Invalid Scores' in App Settings. "
        + "You can also temporarily filter to 'Lead Over CHOpt Threshold' in the Filter modal.")

    let chips = InvalidScoreWarning.make(
        songTitle: "Pulse", reasons: [.drums: .noFallback, .lead: .fallback, .bass: .fallback, .vocals: .fallback],
        instrumentFilter: nil, visibleInstruments: [.lead, .bass, .drums]
    )
    #expect(chips?.charts == [.lead, .bass, .drums])
    #expect(chips?.message == "Pulse has an invalid, filtered-out score on Lead, Bass, and Drums. "
        + "The chips for these instruments reflect the next valid score. "
        + "Because there is no valid other score for Drums, the Drums icon chip is red here.\n\n"
        + "To see the absolute highest scores you've achieved, toggle off 'Filter Invalid Scores' in App Settings. "
        + "You can also temporarily filter to 'Over CHOpt Threshold' in the Filter modal "
        + "when viewing scores for a specific instrument.")

    let over = InvalidScoreWarning.make(
        songTitle: "Pulse", reasons: [.lead: .overThreshold, .bass: .overThreshold], instrumentFilter: nil,
        visibleInstruments: Set(Instrument.allCases)
    )
    #expect(over?.isOverThreshold == true)
    #expect(over?.message == "Pulse has a score on Lead and Bass that exceeds the CHOpt maximum. "
        + "This is the highest unfiltered invalid score.")
}
