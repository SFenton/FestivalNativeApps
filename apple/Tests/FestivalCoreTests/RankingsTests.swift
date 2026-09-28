import Foundation
import Testing
@testable import FestivalCore

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

// MARK: - Per-instrument rankings

@Test func committedRankingsFixtureDecodesAndValidates() throws {
    let data = try Data(contentsOf: fixtureURL("rankings-demo.json"))
    let response = try JSONDecoder().decode(RankingsResponse.self, from: data)
    try response.validate(instrument: .lead)
    #expect(response.entries.count == 3)
    #expect(response.pageCount == 9)
    let first = try #require(response.entries.first)
    #expect(first.rank(for: .totalscore) == 1)
    #expect(first.songsLabel(for: .fcrate) == "39 / 40")
    #expect(first.songsLabel(for: .totalscore) == "40 / 40")
}

@Test func rankingsResponseRejectsMismatchedInstrumentAndOverflowingRows() throws {
    let data = try Data(contentsOf: fixtureURL("rankings-demo.json"))
    let response = try JSONDecoder().decode(RankingsResponse.self, from: data)
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try response.validate(instrument: .bass)
    }
    let overflow = RankingsResponse(
        instrument: "Solo_Guitar", rankBy: "totalscore", page: 1, pageSize: 1,
        totalAccounts: 5, entries: response.entries
    )
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try overflow.validate(instrument: .lead)
    }
}

@Test func ratingValueFollowsSelectedMetric() throws {
    let data = try Data(contentsOf: fixtureURL("rankings-demo.json"))
    let response = try JSONDecoder().decode(RankingsResponse.self, from: data)
    let entry = try #require(response.entries.first)
    #expect(entry.ratingValue(for: .totalscore) == 123456789)
    #expect(entry.ratingValue(for: .maxscore) == 0.998)
    #expect(entry.ratingValue(for: .fcrate) == Double(39) / Double(40))
    #expect(entry.ratingValue(for: .weighted) == 0.9)
    #expect(entry.bayesianValue(for: .adjusted) == 0.0041)
    #expect(entry.bayesianValue(for: .totalscore) == nil)
    let second = response.entries[1]
    // rawWeightedRating is null for the second row; ratingValue falls back to weightedRating.
    #expect(second.ratingValue(for: .weighted) == 0.7)
}

@Test func pageCountUsesTotalAccountsEvenWhenEmpty() {
    let empty = RankingsResponse(
        instrument: "Solo_Guitar", rankBy: "totalscore", page: 1, pageSize: 10,
        totalAccounts: 0, entries: []
    )
    #expect(empty.pageCount == 1)
    let twoPages = RankingsResponse(
        instrument: "Solo_Guitar", rankBy: "totalscore", page: 1, pageSize: 10,
        totalAccounts: 11, entries: []
    )
    #expect(twoPages.pageCount == 2)
}

// MARK: - Band rankings

@Test func committedBandRankingsFixtureDecodesAndValidates() throws {
    let data = try Data(contentsOf: fixtureURL("band-rankings-demo.json"))
    let response = try JSONDecoder().decode(BandRankingsResponse.self, from: data)
    try response.validate(bandType: .duets)
    #expect(response.entries.count == 2)
    #expect(response.pageCount == 6)
    let first = try #require(response.entries.first)
    #expect(first.membersLabel == "Fixture Rank One, Unknown User")
    #expect(first.rank(for: .totalscore) == 1)
}

@Test func bandRankingsResponseRejectsMismatchedBandType() throws {
    let data = try Data(contentsOf: fixtureURL("band-rankings-demo.json"))
    let response = try JSONDecoder().decode(BandRankingsResponse.self, from: data)
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try response.validate(bandType: .trios)
    }
}

@Test func bandRatingValueFollowsSelectedMetricWithNullFallback() throws {
    let data = try Data(contentsOf: fixtureURL("band-rankings-demo.json"))
    let response = try JSONDecoder().decode(BandRankingsResponse.self, from: data)
    let second = try #require(response.entries.last)
    // rawWeightedRating is null for the second row; ratingValue falls back to weightedRating.
    #expect(second.ratingValue(for: .weighted) == 0.4)
    #expect(second.bayesianValue(for: .weighted) == 0.4)
    #expect(second.bayesianValue(for: .fcrate) == nil)
}

// MARK: - Metric coercion

@Test func rankingMetricBandFallbackMatchesWebCoercion() {
    #expect(RankingMetric.adjusted.bandMetric == .adjusted)
    #expect(RankingMetric.weighted.bandMetric == .weighted)
    #expect(RankingMetric.fcrate.bandMetric == .fcrate)
    #expect(RankingMetric.totalscore.bandMetric == .totalscore)
    #expect(RankingMetric.maxscore.bandMetric == .totalscore)
}

// MARK: - Display formatting

@Test func percentileFormattingMatchesWebThresholds() {
    #expect(RankingFormatting.percentile(0.0001) == "Top 0.01%")
    #expect(RankingFormatting.percentile(0.005) == "Top 0.50%")
    #expect(RankingFormatting.percentile(0.03) == "Top 3%")
    #expect(RankingFormatting.percentile(1.5) == "Top 100%")
    #expect(RankingFormatting.percentile(.nan) == "N/A")
}

@Test func percentageFormattingAlwaysShowsOneDecimal() {
    #expect(RankingFormatting.percentage(0.973) == "97.3%")
    #expect(RankingFormatting.percentage(1.0) == "100.0%")
    #expect(RankingFormatting.percentage(0) == "0.0%")
}

@Test func wholeNumberFormattingGroupsThousands() {
    #expect(RankingFormatting.wholeNumber(1_234_567) == "1,234,567")
}

@Test func bayesianFormattingTrimsTrailingZerosByMagnitude() {
    #expect(RankingFormatting.bayesian(0.0041) == "0.0041")
    #expect(RankingFormatting.bayesian(0.05) == "0.05")
    #expect(RankingFormatting.bayesian(0.4) == "0.40")
    #expect(RankingFormatting.bayesian(1.27) == "1.3")
}

@Test func ratingDispatchesToTheRightFormatterPerMetric() {
    #expect(RankingFormatting.rating(0.02, metric: .adjusted) == "Top 2%")
    #expect(RankingFormatting.rating(0.973, metric: .fcrate) == "97.3%")
    #expect(RankingFormatting.rating(1_234_567, metric: .totalscore) == "1,234,567")
}
