import Foundation
import Testing
@testable import FestivalCore

private func entry(_ instrument: Instrument, score: Int, accuracy: Double?, fc: Bool, date: String) -> ScoreHistoryEntry {
    let json = """
    {"songId":"s","instrument":"\(instrument.rawValue)","newScore":\(score),"newRank":1,
     "accuracy":\(accuracy.map { String($0) } ?? "null"),"isFullCombo":\(fc),
     "scoreAchievedAt":"\(date)","changedAt":"\(date)"}
    """
    return try! JSONDecoder().decode(ScoreHistoryEntry.self, from: Data(json.utf8))
}

@Test func selectorOffersOnlyInstrumentsWithHistoryInPoolOrder() {
    let rows = [
        entry(.drums, score: 1, accuracy: nil, fc: false, date: "2024-01-01T00:00:00Z"),
        entry(.lead, score: 2, accuracy: nil, fc: false, date: "2024-01-02T00:00:00Z"),
        entry(.karaoke, score: 3, accuracy: nil, fc: false, date: "2024-01-03T00:00:00Z"),
    ]
    #expect(SongScoreHistoryModel.instruments(with: rows, in: [.lead, .bass, .drums]) == [.lead, .drums])
}

@Test func resolvedInstrumentPrefersTheRequestThenLeadThenTheFirst() {
    #expect(SongScoreHistoryModel.resolvedInstrument(preferred: .drums, available: [.lead, .drums]) == .drums)
    #expect(SongScoreHistoryModel.resolvedInstrument(preferred: .bass, available: [.drums, .lead]) == .lead)
    #expect(SongScoreHistoryModel.resolvedInstrument(preferred: nil, available: [.drums, .bass]) == .drums)
    #expect(SongScoreHistoryModel.resolvedInstrument(preferred: .lead, available: []) == nil)
}

@Test func chartIsChronologicalAndTheListIsBestFirstTopFive() {
    let rows = (1 ... 7).map { day in
        entry(.lead, score: [5, 9, 1, 9, 3, 7, 2][day - 1], accuracy: 990_000, fc: false,
              date: "2024-01-0\(day)T00:00:00Z")
    }.reversed()
    let chronological = SongScoreHistoryModel.chronological(Array(rows), instrument: .lead)
    #expect(chronological.map(\.newScore) == [5, 9, 1, 9, 3, 7, 2])
    let best = SongScoreHistoryModel.bestFirst(chronological, limit: SongScoreHistoryModel.listLimit)
    #expect(best.map(\.newScore) == [9, 9, 7, 5, 3])
    // Equal scores: the newer one first.
    #expect(best[0].scoreAchievedAt == "2024-01-04T00:00:00Z")
    #expect(SongScoreHistoryModel.bestFirst(chronological, limit: nil).count == 7)
}

@Test func barsUseTheWebAccuracyScaleAndGoldForPerfectFullCombos() {
    let perfect = entry(.lead, score: 1, accuracy: 1_000_000, fc: true, date: "2024-01-01T00:00:00Z")
    let nearly = entry(.lead, score: 1, accuracy: 987_600, fc: true, date: "2024-01-01T00:00:00Z")
    let unknown = entry(.lead, score: 1, accuracy: nil, fc: false, date: "2024-01-01T00:00:00Z")
    #expect(SongScoreHistoryModel.accuracyPercent(nearly) == 98.76)
    #expect(SongScoreHistoryModel.accuracyPercent(unknown) == 0)
    #expect(SongScoreHistoryModel.isGold(perfect))
    #expect(!SongScoreHistoryModel.isGold(nearly))
}
