import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

/// Locate a fixture committed under `contracts/fixtures/`.
///
/// - Parameter name: Fixture file name, including its extension.
/// - Returns: Absolute URL to the fixture inside the repository checkout.
private func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contracts/fixtures/\(name)")
}

/// Decode a band rank-history response from inline history JSON.
///
/// - Parameter history: The `history` array's JSON.
/// - Returns: The decoded response.
private func history(_ history: String) throws -> BandRankHistoryResponse {
    let json = """
    {"bandType":"Band_Duets","teamKey":"a:b","days":30,"history":\(history),
     "historyStatus":"current","historyMessage":null}
    """
    return try JSONDecoder().decode(BandRankHistoryResponse.self, from: Data(json.utf8))
}

// MARK: - Header

@Test func bandTitleJoinsMemberNamesLikeTheWeb() {
    #expect(BandPageFormatting.title(memberNames: ["SFentonX", " Player Two "]) == "SFentonX + Player Two")
    #expect(BandPageFormatting.title(memberNames: ["", "  "]) == "Band")
    #expect(BandPageFormatting.title(memberNames: []) == "Band")
}

@Test func bandSubtitleGivesTypeAndAppearancesWithASingular() {
    #expect(BandPageFormatting.subtitle(bandType: .duets, appearances: 1_420) == "Duos • 1,420 appearances")
    #expect(BandPageFormatting.subtitle(bandType: .duets, appearances: 1) == "Duos • 1 appearance")
    #expect(BandPageFormatting.subtitle(bandType: .duets, appearances: -3) == "Duos • 0 appearances")
}

// MARK: - Stat values

@Test func bandStatValuesFollowTheWebFormatters() {
    #expect(BandPageFormatting.rank(1_234) == "#1,234")
    #expect(BandPageFormatting.rank(0) == "—")
    #expect(BandPageFormatting.averageRank(12.34) == "#12.3")
    #expect(BandPageFormatting.averageRank(0) == "—")
    #expect(BandPageFormatting.averageRank(.nan) == "—")
    #expect(BandPageFormatting.accuracy(988_000) == "98.8%")
    #expect(BandPageFormatting.accuracy(0) == "—")
    #expect(BandPageFormatting.stars(4.46) == "4.5")
    #expect(BandPageFormatting.stars(0) == "—")
    #expect(BandPageFormatting.isGoldStars(6))
    #expect(!BandPageFormatting.isGoldStars(5.99))
    #expect(BandPageFormatting.fcRate(0.125) == "12.5%")
    #expect(BandPageFormatting.ofTotal(1_200, 1_640) == "1,200 / 1,640")
}

@Test func bandSongsDescriptionsNameTheBand() {
    #expect(BandPageFormatting.bestSongsDescription("A + B") == "A + B's highest-ranked band songs, sorted by percentile.")
    #expect(BandPageFormatting.worstSongsDescription("A + B") == "A + B's lowest-ranked band songs, sorted by percentile.")
}

// MARK: - Rank history subtitle

@Test func bandHistorySubtitleAddsTheStatusSuffix() {
    let base = "Any-combo ranking progression over the past 30 days."
    #expect(BandPageFormatting.historySubtitle(days: 30, status: "current", message: nil) == base)
    #expect(BandPageFormatting.historySubtitle(days: 30, status: nil, message: nil) == base)
    #expect(
        BandPageFormatting.historySubtitle(days: 30, status: "catching_up", message: nil)
            == "\(base) History is catching up. Current rankings are already fresh."
    )
    #expect(
        BandPageFormatting.historySubtitle(days: 30, status: "stale", message: nil)
            == "\(base) Rank history is behind the latest current rankings."
    )
    #expect(
        BandPageFormatting.historySubtitle(days: 30, status: "disabled", message: nil)
            == "\(base) Rank history is disabled while current rankings remain available."
    )
    #expect(BandPageFormatting.historySubtitle(days: 30, status: "stale", message: "Back soon.") == "\(base) Back soon.")
    #expect(BandPageFormatting.historySubtitle(days: 30, status: "failed", message: "Ignored") == base)
    #expect(BandPageFormatting.historySubtitle(days: 7, status: nil, message: "") == "Any-combo ranking progression over the past 7 days.")
}

// MARK: - Rank history value kind

@Test func rankHistoryValueKindNamesAndFormatsEachMetric() {
    #expect(RankHistoryValueKind.playerTotalScore.title == "Total Score")
    #expect(RankHistoryValueKind.playerTotalScore.rankName == "global rank")
    #expect(RankHistoryValueKind.playerTotalScore.rankSeriesName == "Total Score rank")
    #expect(RankHistoryValueKind.playerTotalScore.text(89_400_000) == 89_400_000.formatted())
    #expect(RankHistoryValueKind.playerTotalScore.tick(1_500_000) == "1.5M")

    #expect(RankHistoryValueKind.band(.adjusted).title == "Adjusted Percentile")
    #expect(RankHistoryValueKind.band(.weighted).title == "Popularity-Weighted Percentile")
    #expect(RankHistoryValueKind.band(.fcrate).title == "FC Rate")
    #expect(RankHistoryValueKind.band(.totalscore).title == "Total Score")
    #expect(RankHistoryValueKind.band(.fcrate).rankName == "band rank")
    #expect(RankHistoryValueKind.playerTotalScore.sentenceName == "Total score")
    #expect(RankHistoryValueKind.playerTotalScore.inlineName == "total score")
    #expect(RankHistoryValueKind.band(.fcrate).sentenceName == "FC rate")
    #expect(RankHistoryValueKind.band(.fcrate).inlineName == "FC rate")
    #expect(RankHistoryValueKind.band(.weighted).inlineName == "popularity-weighted percentile")

    #expect(RankHistoryValueKind.band(.fcrate).tick(0.456) == "46%")
    #expect(RankHistoryValueKind.band(.adjusted).tick(0.0123) == "0.01")
    #expect(RankHistoryValueKind.band(.totalscore).tick(2_000_000) == "2M")
    #expect(RankHistoryValueKind.band(.fcrate).text(0.125) == "12.5%")
    #expect(RankHistoryValueKind.band(.totalscore).text(1_234) == "1,234")
    #expect(RankHistoryValueKind.band(.adjusted).text(0.03) == RankingFormatting.percentile(0.03))
}

// MARK: - Rank history series

@Test func bandHistoryChartValuePrefersRawRatings() throws {
    let response = try history("""
    [{"snapshotDate":"2026-09-27","adjustedSkillRank":3,"weightedRank":4,"fcRateRank":5,"totalScoreRank":6,
      "adjustedSkillRating":0.2,"rawSkillRating":0.1,"weightedRating":0.4,"rawWeightedRating":0.3,
      "fcRate":0.5,"totalScore":1000},
     {"snapshotDate":"2026-09-26","adjustedSkillRank":1,"weightedRank":1,"fcRateRank":1,"totalScoreRank":1,
      "adjustedSkillRating":0.7,"weightedRating":0.8}]
    """)
    let raw = response.history[0]
    #expect(raw.chartValue(for: .adjusted) == 0.1)
    #expect(raw.chartValue(for: .weighted) == 0.3)
    #expect(raw.chartValue(for: .fcrate) == 0.5)
    #expect(raw.chartValue(for: .totalscore) == 1000)
    let adjustedOnly = response.history[1]
    #expect(adjustedOnly.chartValue(for: .adjusted) == 0.7)
    #expect(adjustedOnly.chartValue(for: .weighted) == 0.8)
    #expect(adjustedOnly.chartValue(for: .fcrate) == nil)
    #expect(adjustedOnly.chartValue(for: .totalscore) == nil)
}

@Test func bandHistoryRankedChronologicalDropsUnrankedDaysAndSortsOldestFirst() throws {
    let response = try history("""
    [{"snapshotDate":"2026-09-28","adjustedSkillRank":2,"weightedRank":0,"fcRateRank":1,"totalScoreRank":1},
     {"snapshotDate":"2026-09-26","adjustedSkillRank":4,"weightedRank":3,"fcRateRank":1,"totalScoreRank":1},
     {"snapshotDate":"2026-09-27","adjustedSkillRank":0,"weightedRank":2,"fcRateRank":1,"totalScoreRank":1}]
    """)
    #expect(response.rankedChronological(for: .adjusted).map(\.snapshotDate) == ["2026-09-26", "2026-09-28"])
    #expect(response.rankedChronological(for: .weighted).map(\.snapshotDate) == ["2026-09-26", "2026-09-27"])
    #expect(response.rankedChronological(for: .fcrate).count == 3)
}

@Test func bandProfileEnvelopeCarriesTheRankedTeamCount() throws {
    let data = try Data(contentsOf: fixtureURL("band-detail-demo.json"))
    let envelope = try JSONDecoder().decode(BandProfileEnvelope.self, from: data)
    #expect(envelope.totalTeams == 12)
}

// MARK: - Percentile pill

@Test func percentileBucketClampsLikeTheWeb() {
    #expect(ScoreFormatting.percentileBucket(percentile: 0) == "Top 1%")
    #expect(ScoreFormatting.percentileBucket(percentile: 0.4) == "Top 1%")
    #expect(ScoreFormatting.percentileBucket(percentile: 4.2) == "Top 5%")
    #expect(ScoreFormatting.percentileBucket(percentile: 61) == "Top 70%")
    #expect(ScoreFormatting.percentileBucket(percentile: 250) == "Top 100%")
    #expect(ScoreFormatting.percentileBucket(percentile: .nan) == nil)
    #expect(ScoreFormatting.percentileBucket(rank: 12, totalEntries: 340) == "Top 4%")
    #expect(ScoreFormatting.percentileBucket(rank: 0, totalEntries: 340) == nil)
}

// MARK: - Stat links

@Test func bandRankTilesLinkToTheBandsRankingsPage() {
    #expect(PlayerStatLinks.bandRank(1, metric: .adjusted, bandType: .duets) == .bandRankings(.duets, rankBy: .adjusted, page: 1))
    #expect(PlayerStatLinks.bandRank(25, metric: .fcrate, bandType: .duets) == .bandRankings(.duets, rankBy: .fcrate, page: 1))
    #expect(PlayerStatLinks.bandRank(26, metric: .totalscore, bandType: .duets) == .bandRankings(.duets, rankBy: .totalscore, page: 2))
    #expect(PlayerStatLinks.bandRank(0, metric: .weighted, bandType: .duets) == nil)
    #expect(PlayerStatLink.bandRankings(.duets, rankBy: .adjusted, page: 1).requiresSelection == false)
}

@Test func bandBestSongTileLinksOnlyWithARankedBestSong() {
    #expect(PlayerStatLinks.bandBestSong(bestRank: 3, songId: "song-1") == .bandSongDetail(songId: "song-1"))
    #expect(PlayerStatLinks.bandBestSong(bestRank: 0, songId: "song-1") == nil)
    #expect(PlayerStatLinks.bandBestSong(bestRank: 3, songId: nil) == nil)
    #expect(PlayerStatLinks.bandBestSong(bestRank: 3, songId: "") == nil)
}
