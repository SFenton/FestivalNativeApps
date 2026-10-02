import Foundation
import Testing
@testable import FestivalCore

// MARK: - Visible columns

@Test func songLeaderboardOnPhoneWidthsShowsOnlyCoreColumns() {
    // Portrait iPhones (320–440 pt) and unmeasured widths: rank, name, score and the
    // native-kept accuracy badge; no season, difficulty or stars (web < 520 px).
    for width in [0.0, -10, .nan, .infinity, 320, 402, 440, 519.9] {
        let columns = LeaderboardRowColumns.fit(.songLeaderboard, width: width)
        #expect(columns.showsAccuracy)
        #expect(!columns.showsSeason)
        #expect(!columns.showsDifficulty)
        #expect(!columns.showsStars)
    }
}

@Test func songLeaderboardAddsSeasonThenStarsAsWidthGrows() {
    let medium = LeaderboardRowColumns.fit(.songLeaderboard, width: 520)
    #expect(medium.showsSeason && medium.showsDifficulty && !medium.showsStars)
    let belowWide = LeaderboardRowColumns.fit(.songLeaderboard, width: 767.5)
    #expect(belowWide.showsSeason && !belowWide.showsStars)
    // iPad portrait / Mac windows reach the web's 768 px stars column.
    for width in [768.0, 820, 1_024, 1_440] {
        let wide = LeaderboardRowColumns.fit(.songLeaderboard, width: width)
        #expect(wide.showsAccuracy && wide.showsSeason && wide.showsDifficulty && wide.showsStars)
    }
}

@Test func topScoreCardsMeasureTheCardAndNeverShowStars() {
    #expect(!LeaderboardRowColumns.fit(.topScores, width: 361).showsSeason)
    let wide = LeaderboardRowColumns.fit(.topScores, width: 900)
    #expect(wide.showsSeason && wide.showsDifficulty && wide.showsAccuracy)
    #expect(!wide.showsStars)
    // Same breakpoint as the existing season policy.
    #expect(LeaderboardRowColumns.mediumBreakpoint == ScoreRowSeasonPolicy.breakpoint)
    for width in [100.0, 519, 520, 2_000] {
        #expect(
            LeaderboardRowColumns.fit(.topScores, width: width).showsSeason
                == ScoreRowSeasonPolicy.showsColumn(.topScores, width: width)
        )
    }
}

@Test func rankingsNeverShowScoreMetadataColumns() {
    for width in [320.0, 1_440] {
        let columns = LeaderboardRowColumns.fit(.rankings, width: width, ranks: [1])
        #expect(!columns.showsAccuracy && !columns.showsSeason)
        #expect(!columns.showsDifficulty && !columns.showsStars)
    }
}

// MARK: - Shared widths

@Test func rankColumnUsesTheLongestRankIncludingPinnedRows() {
    // Top ten: `#10` sets the width so `#1`…`#9` names line up with it.
    let topTen = LeaderboardRowColumns.fit(.topScores, width: 361, ranks: Array(1...10))
    #expect(topTen.rankLabel == "#10")
    #expect(topTen.referenceRankWidth == 38) // ceil(3 × 8.5) + 12, web computeRankWidth
    // A spotlight row far below the top ten widens the whole section.
    let spotlight = LeaderboardRowColumns.fit(.topScores, width: 361, ranks: Array(1...10) + [12_345])
    #expect(spotlight.rankLabel == LeaderboardRowColumns.rankLabel(12_345))
    #expect(spotlight.referenceRankWidth == (Double(spotlight.rankLabel!.count) * 8.5).rounded(.up) + 12)
    // Order does not matter; the pinned row may come first.
    let reordered = LeaderboardRowColumns.fit(.songLeaderboard, width: 402, ranks: [12_345] + Array(1...10))
    #expect(reordered.rankLabel == spotlight.rankLabel)
}

@Test func rankColumnIsTheSameAtNarrowAndWideWidths() {
    let ranks = Array(76...100)
    let narrow = LeaderboardRowColumns.fit(.songLeaderboard, width: 402, ranks: ranks)
    let wide = LeaderboardRowColumns.fit(.songLeaderboard, width: 1_024, ranks: ranks)
    #expect(narrow.rankLabel == "#100" && wide.rankLabel == "#100")
    #expect(narrow.referenceRankWidth == 46 && wide.referenceRankWidth == 46)
}

@Test func emptyOrInvalidRanksFallBackToTheWebDefault() {
    let empty = LeaderboardRowColumns.fit(.rankings, width: 402)
    #expect(empty.rankLabel == nil)
    #expect(empty.referenceRankWidth == LeaderboardRowColumns.defaultRankWidth)
    #expect(LeaderboardRowColumns.fit(.rankings, width: 402, ranks: [0, -3]).rankLabel == nil)
    #expect(LeaderboardRowColumns.unconstrained.rankLabel == nil)
    #expect(LeaderboardRowColumns.unconstrained.showsAccuracy)
}

@Test func scoreColumnUsesTheLongestScore() {
    let columns = LeaderboardRowColumns.fit(
        .songLeaderboard, width: 402, ranks: [1, 2, 3], scores: [99_900, 1_234_567, 708_315]
    )
    #expect(columns.scoreLabel == LeaderboardRowColumns.scoreLabel(1_234_567))
    #expect(columns.scoreCharacters == LeaderboardRowColumns.scoreLabel(1_234_567).count)
    let none = LeaderboardRowColumns.fit(.songLeaderboard, width: 402, scores: [-1])
    #expect(none.scoreLabel == nil && none.scoreCharacters == 1)
}

@Test func ratingColumnUsesTheLongestRatingLabel() {
    let ratings = ["Top 1%", "Top 0.03%", "Top 12%"]
    let columns = LeaderboardRowColumns.fit(.rankings, width: 402, ranks: [1, 2, 3], ratings: ratings)
    #expect(columns.ratingLabel == "Top 0.03%")
    #expect(LeaderboardRowColumns.fit(.rankings, width: 402, ratings: ["", ""]).ratingLabel == nil)
    // Equal lengths keep the first label.
    #expect(LeaderboardRowColumns.widest(["97.3%", "88.1%"]) == "97.3%")
}

@Test func rowLabelsMatchTheRowFormatting() {
    #expect(LeaderboardRowColumns.rankLabel(7) == "#\(7.formatted())")
    #expect(LeaderboardRowColumns.rankLabel(1_234) == "#\(1_234.formatted())")
    #expect(LeaderboardRowColumns.scoreLabel(709_230) == 709_230.formatted())
}

/// A decoded rankings row whose rank is `rank` and total score is `totalScore`.
private func rankingRow(
    rank: Int, totalScore: Int, songsPlayed: Int = 10, totalCharted: Int = 20, fullCombos: Int = 5
) throws -> AccountRankingEntry {
    let data = Data("""
    {"accountId":"a\(rank)","displayName":"Fixture","songsPlayed":\(songsPlayed),
     "totalChartedSongs":\(totalCharted),"coverage":0.5,"rawSkillRating":0.01,
     "adjustedSkillRating":0.01,"adjustedSkillRank":\(rank),"weightedRating":0.02,
     "weightedRank":\(rank),"fcRate":0.4,"fcRateRank":\(rank),"totalScore":\(totalScore),
     "totalScoreRank":\(rank),"maxScorePercent":0.9,"maxScorePercentRank":\(rank),
     "avgAccuracy":0.95,"fullComboCount":\(fullCombos),"avgStars":4.0,"bestRank":1,"avgRank":2.0}
    """.utf8)
    return try JSONDecoder().decode(AccountRankingEntry.self, from: data)
}

@Test func rankingsSectionsShareTheMetricsRankAndRatingColumns() throws {
    // A top-ten card plus the selected player's pinned row at rank 1,234.
    let rows = try (1...10).map { try rankingRow(rank: $0, totalScore: 900_000 - $0) }
        + [rankingRow(rank: 1_234, totalScore: 12_345_678)]
    let columns = LeaderboardRowColumns.rankings(rows, metric: .totalscore)
    #expect(columns.rankLabel == LeaderboardRowColumns.rankLabel(1_234))
    #expect(columns.ratingLabel == RankingFormatting.rating(12_345_678, metric: .totalscore))
    #expect(!columns.showsSeason && !columns.showsAccuracy)
    let empty = LeaderboardRowColumns.rankings([], metric: .adjusted)
    #expect(empty.rankLabel == nil && empty.ratingLabel == nil)
}

// MARK: - Songs column (#38)

@Test func rankingsSectionsShareTheWidestSongsLabel() throws {
    let rows = try [
        rankingRow(rank: 1, totalScore: 900, songsPlayed: 728, totalCharted: 729, fullCombos: 3),
        rankingRow(rank: 2, totalScore: 800, songsPlayed: 9, totalCharted: 729, fullCombos: 12),
    ]
    #expect(LeaderboardRowColumns.rankings(rows, metric: .totalscore).songsLabel == "728 / 729")
    // FC rate shows full combos instead of songs played.
    #expect(LeaderboardRowColumns.rankings(rows, metric: .fcrate).songsLabel == "12 / 729")
    #expect(LeaderboardRowColumns.rankings([], metric: .totalscore).songsLabel == nil)
    #expect(LeaderboardRowColumns.rankings(rows, metric: .totalscore).showsSongs)
}

@Test func songsFitOnlyWhenTheWidestRowFits() {
    #expect(LeaderboardRowColumns.songsFit(availableWidth: 370, requiredWidth: 369.5))
    #expect(LeaderboardRowColumns.songsFit(availableWidth: 370, requiredWidth: 370))
    // A fraction of a point too wide would already truncate a name.
    #expect(!LeaderboardRowColumns.songsFit(availableWidth: 370, requiredWidth: 370.25))
    #expect(!LeaderboardRowColumns.songsFit(availableWidth: 320, requiredWidth: 402))
}

@Test func songsFitKeepsSongsUntilBothWidthsAreMeasured() {
    for (available, required) in [(0.0, 400.0), (370, 0), (-1, 400), (.infinity, 400), (370, .nan)] {
        #expect(LeaderboardRowColumns.songsFit(availableWidth: available, requiredWidth: required))
    }
}

@Test func fittingSongsDecidesForTheWholeSection() throws {
    let rows = try (1...5).map { try rankingRow(rank: $0, totalScore: 90_000_000 - $0) }
    let columns = LeaderboardRowColumns.rankings(rows, metric: .totalscore)
    let narrow = columns.fittingSongs(availableWidth: 370, requiredWidth: 402)
    #expect(!narrow.showsSongs)
    // Everything else about the section is unchanged.
    var restored = narrow
    restored.showsSongs = true
    #expect(restored == columns)
    #expect(columns.fittingSongs(availableWidth: 700, requiredWidth: 402).showsSongs)
    // Re-fitting a hidden section at a wider width (rotation) shows songs again.
    #expect(narrow.fittingSongs(availableWidth: 700, requiredWidth: 402).showsSongs)
}

@Test func fittingSongsKeepsAnEmptySongsColumnShown() {
    let columns = LeaderboardRowColumns.fit(.rankings, width: 0, ranks: [1], ratings: ["1"])
    #expect(columns.songsLabel == nil)
    #expect(columns.fittingSongs(availableWidth: 100, requiredWidth: 400).showsSongs)
}
