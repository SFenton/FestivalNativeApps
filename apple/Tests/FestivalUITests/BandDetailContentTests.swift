import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// Decode one value from inline JSON.
private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

/// A ranked duo with distinct values per metric (web `BandStatisticsSection` inputs).
private func detail(bestRank: Int = 3, fullCombos: Int = 12) throws -> BandDetail {
    try decode(BandDetail.self, """
    {"bandId":"b","comboId":null,"teamKey":"a:b",
     "members":[{"accountId":"a","displayName":"Ana","instruments":["Solo_Guitar","Solo_Drums"]},
                {"accountId":"b","displayName":null,"instruments":["Solo_Bass"]}],
     "configurations":[],"songsPlayed":1420,"totalChartedSongs":1640,"coverage":0.87,
     "rawSkillRating":0.03,"adjustedSkillRating":0.03,"adjustedSkillRank":7,
     "weightedRating":0.04,"weightedRank":26,"fcRate":0.125,"fcRateRank":51,
     "totalScore":123456789,"totalScoreRank":3,"avgAccuracy":988000,"fullComboCount":\(fullCombos),
     "avgStars":6,"bestRank":\(bestRank),"avgRank":12.34,"rawWeightedRating":0.04,"computedAt":null}
    """)
}

private func songEntry(rank: Int, total: Int, percentile: Double) throws -> BandSongPerformanceEntry {
    try decode(BandSongPerformanceEntry.self, """
    {"songId":"song-1","comboId":null,"rank":\(rank),"totalEntries":\(total),"percentile":\(percentile),
     "score":95000,"accuracy":970000,"isFullCombo":true,"stars":5,"season":10,"endTime":null}
    """)
}

private func song(year: Int? = 2019) throws -> Song {
    let yearField = year.map { ",\"year\":\($0)" } ?? ""
    return try decode(Song.self, """
    {"songId":"song-1","title":"Pulse","artist":"Fixture Artist"\(yearField)}
    """)
}

// MARK: - Summary and Statistics tiles

@MainActor
@Test func bandSummaryTilesAreTypeAppearancesAndMembers() throws {
    let tiles = BandDetailScreen.summaryTiles(try detail(), bandType: .duets)
    #expect(tiles.map(\.label) == ["Type", "Appearances", "Members"])
    #expect(tiles.map(\.value) == ["Duos", 1_420.formatted(), "2"])
    #expect(tiles.allSatisfy { $0.link == nil })
    #expect(BandDetailScreen.summaryTiles(try detail(), bandType: nil).first?.value == "—")
}

@MainActor
@Test func bandStatisticsTilesFollowTheWebOrderValuesAndLinks() throws {
    let tiles = BandDetailScreen.statisticsTiles(try detail(), bandType: .duets, bestSongId: "song-1")
    #expect(tiles.map(\.id) == [
        "adjusted-rank", "weighted-rank", "fc-rate-rank", "total-score-rank", "songs-played",
        "full-combos", "total-score", "fc-rate", "avg-accuracy", "avg-stars", "best-song-rank", "avg-rank",
    ])
    let byID = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, $0) })
    #expect(byID["adjusted-rank"]?.value == "#7")
    #expect(byID["adjusted-rank"]?.link == .bandRankings(.duets, rankBy: .adjusted, page: 1))
    #expect(byID["weighted-rank"]?.link == .bandRankings(.duets, rankBy: .weighted, page: 2))
    #expect(byID["fc-rate-rank"]?.link == .bandRankings(.duets, rankBy: .fcrate, page: 3))
    #expect(byID["total-score-rank"]?.link == .bandRankings(.duets, rankBy: .totalscore, page: 1))
    #expect(byID["songs-played"]?.value == "\(1_420.formatted()) / \(1_640.formatted())")
    #expect(byID["songs-played"]?.link == nil)
    #expect(byID["full-combos"]?.tint == nil)
    #expect(byID["fc-rate"]?.value == "12.5%")
    #expect(byID["avg-accuracy"]?.value == "98.8%")
    #expect(byID["avg-stars"]?.goldStars == true)
    #expect(byID["best-song-rank"]?.link == .bandSongDetail(songId: "song-1"))
    #expect(byID["avg-rank"]?.value == "#12.3")
}

@MainActor
@Test func bandStatisticsTilesDropLinksThatCannotBeFollowed() throws {
    let plain = BandDetailScreen.statisticsTiles(
        try detail(), bandType: .duets, bestSongId: "song-1", linkFilter: { _ in nil }
    )
    #expect(plain.allSatisfy { $0.link == nil })
    let noType = BandDetailScreen.statisticsTiles(try detail(), bandType: nil, bestSongId: nil)
    #expect(noType.allSatisfy { $0.link == nil })
    let unranked = BandDetailScreen.statisticsTiles(try detail(bestRank: 0), bandType: .duets, bestSongId: "song-1")
    #expect(unranked.first { $0.id == "best-song-rank" }?.link == nil)
}

@MainActor
@Test func bandFullCombosTileTurnsGoldWhenEverySongIsFullCombo() throws {
    let tiles = BandDetailScreen.statisticsTiles(try detail(fullCombos: 1_640), bandType: .duets, bestSongId: nil)
    #expect(tiles.first { $0.id == "full-combos" }?.tint != nil)
}

// MARK: - Member cards

@MainActor
@Test func bandMemberCardSpeaksTheWebLabelAndInstruments() throws {
    let members = try detail().members
    #expect(BandMemberCard.spokenLabel(members[0]) == "View Ana, Lead, Drums")
    #expect(BandMemberCard.spokenLabel(members[1]) == "View Unknown User, Bass")
}

// MARK: - Song rows

@MainActor
@Test func bandSongRowBucketsFromRankOverEntries() throws {
    #expect(BandSongRow.percentileDisplay(try songEntry(rank: 12, total: 340, percentile: 0.035)) == "Top 4%")
    #expect(BandSongRow.percentileDisplay(try songEntry(rank: 0, total: 0, percentile: 0.42)) == "Top 50%")
}

@MainActor
@Test func bandSongRowReadsTitleSubtitleAndRank() throws {
    let entry = try songEntry(rank: 12, total: 340, percentile: 0.035)
    #expect(BandSongRow.title(try song()) == "Pulse")
    #expect(BandSongRow.title(nil) == "Unknown Song")
    #expect(BandSongRow.subtitle(try song()) == "Fixture Artist \u{00B7} 2019")
    #expect(BandSongRow.subtitle(try song(year: nil)) == "Fixture Artist")
    #expect(BandSongRow.subtitle(nil) == nil)
    #expect(BandSongRow.spokenLabel(entry, song: try song()) == "Pulse, Top 4%, rank 12 of 340")
    #expect(BandSongRow.spokenLabel(try songEntry(rank: 0, total: 0, percentile: 0.42), song: nil) == "Unknown Song, Top 50%")
}

// MARK: - Rank history chart

@MainActor
@Test func bandRankHistoryPointsPlotTheMetricAgainstRankedTeams() throws {
    let response = try decode(BandRankHistoryResponse.self, """
    {"bandType":"Band_Duets","teamKey":"a:b","days":30,"historyStatus":"current","historyMessage":null,
     "history":[
      {"snapshotDate":"2026-09-27","adjustedSkillRank":3,"weightedRank":4,"fcRateRank":5,"totalScoreRank":6,
       "fcRate":0.5,"totalScore":1000,"totalRankedTeams":80},
      {"snapshotDate":"2026-09-26","adjustedSkillRank":2,"weightedRank":2,"fcRateRank":9,"totalScoreRank":2}]}
    """)
    let points = RankHistoryCharts.points(
        response.rankedChronological(for: .fcrate), metric: .fcrate, totalRankedTeams: 100
    )
    #expect(points.map(\.id) == ["2026-09-26", "2026-09-27"])
    #expect(points.map(\.index) == [0, 1])
    #expect(points.map(\.rank) == [9, 5])
    #expect(points.map(\.rankedAccountCount) == [100, 80])
    #expect(points.map(\.hasValue) == [false, true])
    #expect(RankHistoryCharts.accessibilityValue(points[1], kind: .band(.fcrate)) == "Rank 5 of 80, FC rate 50.0%")
    #expect(RankHistoryCharts.accessibilityValue(points[0], kind: .band(.fcrate)) == "Rank 9 of 100")

    let descriptor = RankHistoryDescriptor(points: points, valueKind: .band(.fcrate), title: "Band rank history")
        .makeChartDescriptor()
    #expect(descriptor.title == "Band rank history")
    #expect(descriptor.series.map(\.name) == ["FC rate", "FC Rate rank"])
    #expect(descriptor.additionalAxes.first?.title == "Band rank")
    #expect(descriptor.summary == "2 daily snapshots. Latest rank 5, up 4 places.")

    // An older snapshot ranked below the current board's size keeps no "of" total.
    let shrunk = RankHistoryCharts.points(
        response.rankedChronological(for: .fcrate), metric: .fcrate, totalRankedTeams: 8
    )
    #expect(shrunk.map(\.rankedAccountCount) == [nil, 80])
    #expect(RankHistoryCharts.accessibilityValue(shrunk[0], kind: .band(.fcrate)) == "Rank 9")
}
