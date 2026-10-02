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

// MARK: - Instrument switch (issue #31)

@Test func pagingShowsEveryRowUntilTheChartIsMeasured() {
    #expect(SongScoreHistoryModel.paging(count: 9, chartWidth: 0).pageSize == 9)
    #expect(!SongScoreHistoryModel.paging(count: 9, chartWidth: 0).needsPagination)
    // 400 pt chart: (400 - 96 + 8) / (96 + 8) = 3 bars a page.
    let measured = SongScoreHistoryModel.paging(count: 9, chartWidth: 400)
    #expect(measured.pageSize == RankHistoryPaging.pageSize(forPlotWidth: 400 - SongScoreHistoryModel.axisAllowance))
    #expect(measured.pageSize == 3)
    #expect(measured.needsPagination)
}

@Test func pagerSpaceIsReservedWhenAnySelectableInstrumentPages() {
    let lead = (1 ... 4).map { day in
        entry(.lead, score: day, accuracy: nil, fc: false, date: "2024-01-0\(day)T00:00:00Z")
    }
    let bass = [entry(.bass, score: 1, accuracy: nil, fc: false, date: "2024-01-01T00:00:00Z")]
    let rows = lead + bass
    // Lead (4 rows) pages at 3 bars a page, so Bass keeps the pager row too.
    #expect(SongScoreHistoryModel.reservesPager(rows, instruments: [.lead, .bass], chartWidth: 400))
    // Only Bass selectable: nothing pages, no reserved row.
    #expect(!SongScoreHistoryModel.reservesPager(rows, instruments: [.bass], chartWidth: 400))
    // Wide enough for every row on one page.
    #expect(!SongScoreHistoryModel.reservesPager(rows, instruments: [.lead, .bass], chartWidth: 2_000))
    // Not measured yet.
    #expect(!SongScoreHistoryModel.reservesPager(rows, instruments: [.lead, .bass], chartWidth: 0))
}

@Test func swapFadesOnlyARealChangeAndIsInstantUnderReduceMotion() {
    #expect(ScoreHistorySwap.plan(displayed: .lead, target: .bass, reduceMotion: false) == .fade)
    #expect(ScoreHistorySwap.plan(displayed: .lead, target: .bass, reduceMotion: true) == .instant)
    // Choosing the shown instrument again (also mid-fade) settles back to fully visible.
    #expect(ScoreHistorySwap.plan(displayed: .lead, target: .lead, reduceMotion: false) == .settle)
    #expect(ScoreHistorySwap.plan(displayed: nil, target: .lead, reduceMotion: false) == .instant)
    #expect(ScoreHistorySwap.plan(displayed: .lead, target: nil, reduceMotion: false) == .none)
    #expect(ScoreHistorySwap.fadeOutSeconds < ScoreHistorySwap.fadeInSeconds)
}
