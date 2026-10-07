import Foundation
import Testing
@testable import FestivalCore

/// Build one fixture entry with only the fields a test cares about.
private func entry(
    score: Int, date: String, accuracy: Double? = nil, fc: Bool? = nil, season: Int? = nil
) -> ScoreHistoryEntry {
    ScoreHistoryEntry(
        songId: "fixture-song", instrument: Instrument.lead.rawValue, oldScore: nil,
        newScore: score, oldRank: nil, newRank: 1, accuracy: accuracy, isFullCombo: fc,
        stars: nil, percentile: nil, season: season, scoreAchievedAt: date,
        seasonRank: nil, allTimeRank: nil, difficulty: nil, changedAt: date
    )
}

// MARK: - Sort

@Test func sortsByScoreDescendingByDefault() {
    let entries = [entry(score: 100, date: "2024-01-01T00:00:00Z"), entry(score: 300, date: "2024-01-02T00:00:00Z"), entry(score: 200, date: "2024-01-03T00:00:00Z")]
    let sorted = PlayerScoreHistorySort.sorted(entries, mode: .score, ascending: false)
    #expect(sorted.map(\.newScore) == [300, 200, 100])
}

@Test func sortsByDateAscending() {
    let entries = [entry(score: 100, date: "2024-01-03T00:00:00Z"), entry(score: 300, date: "2024-01-01T00:00:00Z"), entry(score: 200, date: "2024-01-02T00:00:00Z")]
    let sorted = PlayerScoreHistorySort.sorted(entries, mode: .date, ascending: true)
    #expect(sorted.map(\.newScore) == [300, 200, 100])
}

@Test func accuracyTiesBreakByFullComboThenScoreThenDate() {
    let a = entry(score: 100, date: "2024-01-01T00:00:00Z", accuracy: 990_000, fc: false)
    let b = entry(score: 200, date: "2024-01-02T00:00:00Z", accuracy: 990_000, fc: true)
    let sorted = PlayerScoreHistorySort.sorted([a, b], mode: .accuracy, ascending: false)
    // Equal accuracy: full combo wins the tiebreak, so b sorts first descending.
    #expect(sorted.first?.newScore == 200)
}

@Test func highScoreIndexPicksTheSingleMaximum() {
    let entries = [entry(score: 100, date: "2024-01-01T00:00:00Z"), entry(score: 300, date: "2024-01-02T00:00:00Z"), entry(score: 200, date: "2024-01-03T00:00:00Z")]
    #expect(PlayerScoreHistorySort.highScoreIndex(in: entries) == 1)
    #expect(PlayerScoreHistorySort.highScoreIndex(in: []) == nil)
}

@Test func defaultSortIsScoreDescendingLikeTheWeb() {
    #expect(PlayerScoreHistorySort.defaultMode == .score)
    #expect(PlayerScoreHistorySort.defaultAscending == false)
    #expect(!PlayerScoreHistorySort.isCustomized(mode: .score, ascending: false))
    #expect(PlayerScoreHistorySort.isCustomized(mode: .score, ascending: true))
    #expect(PlayerScoreHistorySort.isCustomized(mode: .date, ascending: false))
}

@Test func sortSpokenValueNamesModeAndDirection() {
    #expect(PlayerScoreHistorySort.spokenValue(mode: .score, ascending: false) == "Score, descending")
    #expect(PlayerScoreHistorySort.spokenValue(mode: .season, ascending: true) == "Season, ascending")
}

@Test func highlightFollowsTheBestRowAfterResorting() {
    let entries = [entry(score: 100, date: "2024-01-01T00:00:00Z", season: 2), entry(score: 300, date: "2024-01-02T00:00:00Z", season: 1), entry(score: 200, date: "2024-01-03T00:00:00Z", season: 3)]
    let byDate = PlayerScoreHistorySort.sorted(entries, mode: .date, ascending: false)
    #expect(PlayerScoreHistorySort.highScoreIndex(in: byDate) == 1)
    let bySeason = PlayerScoreHistorySort.sorted(entries, mode: .season, ascending: true)
    #expect(bySeason.map(\.newScore) == [300, 100, 200])
    #expect(PlayerScoreHistorySort.highScoreIndex(in: bySeason) == 0)
}

// MARK: - Response validation and payload filtering

@Test func historyResponseRejectsMismatchedAccountOrCount() throws {
    let data = Data("""
    {"accountId":"acc-1","count":1,"history":[]}
    """.utf8)
    let response = try JSONDecoder().decode(PlayerHistoryResponse.self, from: data)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try response.validate(accountId: "acc-1")
    }
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try response.validate(accountId: "acc-2")
    }
}

@Test func payloadEntriesAreScopedToSongAndInstrument() {
    let matching = entry(score: 100, date: "2024-01-01T00:00:00Z")
    let otherInstrument = ScoreHistoryEntry(
        songId: "fixture-song", instrument: Instrument.bass.rawValue, oldScore: nil,
        newScore: 50, oldRank: nil, newRank: 1, accuracy: nil, isFullCombo: nil, stars: nil,
        percentile: nil, season: nil, scoreAchievedAt: "2024-01-01T00:00:00Z",
        seasonRank: nil, allTimeRank: nil, difficulty: nil, changedAt: "2024-01-01T00:00:00Z"
    )
    let response = PlayerHistoryResponse(
        accountId: "acc-1", count: 2, history: [matching, otherInstrument],
        status: nil, notYetPublished: nil
    )
    let payload = PlayerHistoryPayload(
        response: response, state: .available, publicationId: 1,
        observedPublicationId: 1, isStale: false
    )
    let filtered = payload.entries(songId: "fixture-song", instrument: .lead)
    #expect(filtered.count == 1)
    #expect(filtered.first?.newScore == 100)
}
