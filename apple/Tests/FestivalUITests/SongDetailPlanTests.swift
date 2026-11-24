import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Song Detail plan (shared by the SwiftUI screen and the UIKit port)

@Test func pathInstrumentsDropKaraokeAndHiddenCharts() {
    let visible: Set<Instrument> = [.lead, .karaoke, .drums]
    let paths = SongDetailPlan.pathInstruments(visible: visible)
    #expect(!paths.contains(.karaoke))
    #expect(Set(paths) == [.lead, .drums])
    // `Instrument` order, not the set's.
    #expect(paths == Instrument.allCases.filter { $0 == .lead || $0 == .drums })
}

@Test func quickLinksListIntensityHistoryCardsThenBands() {
    let withHistory = SongDetailPlan.quickLinkSections(previewInstruments: [.lead, .bass], showsScoreHistory: true)
    #expect(withHistory.map(\.id) == [
        "intensity", "score-history", "instrument-\(Instrument.lead.rawValue)", "instrument-\(Instrument.bass.rawValue)",
    ] + BandType.allCases.map { "band-\($0.rawValue)" })
    let without = SongDetailPlan.quickLinkSections(previewInstruments: [.lead], showsScoreHistory: false)
    #expect(!without.contains { $0.id == "score-history" })
    #expect(without.first?.id == "intensity")
}

@Test func bandQuickLinkUsesTheBandSymbol() {
    for band in BandType.allCases {
        #expect(SongDetailPlan.bandQuickLink(band).id == "band-\(band.rawValue)")
        #expect(SongDetailPlan.bandQuickLink(band).title == band.label)
    }
}

// MARK: - Score History chart maths

@Test func accuracyColourRampRunsRedToGreen() {
    let low = SongScoreHistoryChartMath.accuracyRGB(0)
    let high = SongScoreHistoryChartMath.accuracyRGB(100)
    #expect(abs(low.red - 220.0 / 255) < 0.0001 && abs(low.green - 40.0 / 255) < 0.0001)
    #expect(abs(high.red - 46.0 / 255) < 0.0001 && abs(high.green - 204.0 / 255) < 0.0001)
    // Out-of-range input clamps.
    #expect(SongScoreHistoryChartMath.accuracyRGB(-50).red == low.red)
    #expect(SongScoreHistoryChartMath.accuracyRGB(500).blue == high.blue)
}

@Test func scoreAxisLabelsAbbreviateThousands() {
    #expect(SongScoreHistoryChartMath.scoreAxisLabel(850) == "850")
    #expect(SongScoreHistoryChartMath.scoreAxisLabel(12_400) == "12k")
}

@Test func scoreTicksStartAtZeroAndStayInRange() {
    for top in [1.0, 99.0, 12_345.0, 1_000_000.0] {
        let ticks = SongScoreHistoryChartMath.scoreTicks(top: top)
        #expect(ticks.first == 0)
        #expect(ticks.allSatisfy { $0 <= top })
        #expect(ticks.count >= 2 && ticks.count <= 7)
        #expect(ticks == ticks.sorted())
    }
}

@Test func scoreTicksKeepReferenceDensityAcrossInstrumentSwaps() {
    #expect(SongScoreHistoryChartMath.scoreTicks(top: 850_000 * 1.1) == [0, 250_000, 500_000, 750_000])
    #expect(SongScoreHistoryChartMath.scoreTicks(top: 612_000 * 1.1) == [0, 200_000, 400_000, 600_000])
}

@Test func sharedHistoryAxisFitsQuarterStepsOnAMillionsScale() {
    #expect(HistoryAxisTicks.linear(top: 98_340_000, intervals: 4) == [0, 25_000_000, 50_000_000, 75_000_000])
}

@Test func interruptedChartSlideStartsFromTheDisplayedBars() {
    let plot = CGRect(x: 20, y: 0, width: 200, height: 100)
    let newest = HistoryChartWindow(4..<6)
    let older = HistoryChartWindow(2..<4)
    let sliding = newest.sliding(to: older, time: 0.5)
    #expect(abs(sliding.x(4, in: plot) - 206.9) < 0.1)
    #expect(sliding.indexes(in: 0..<6, padding: 1) == 2..<6)
    let reversed = sliding.sliding(to: newest, time: 0.01)
    #expect(reversed.x(4, in: plot) < sliding.x(4, in: plot))
    #expect(reversed.x(4, in: plot) > 200)
    #expect(sliding.sliding(to: newest, time: 1).x(4, in: plot) == 70)
}

@Test func historyDatesKeepTheNewestAndPinAnEdgeWithoutOverlap() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 20)
    let centres: [CGFloat] = [8, 41, 65, 92]
    let widths: [CGFloat] = [20, 32, 32, 28]
    #expect(HistoryChartWindow.dateLabelLefts(centres: centres, widths: widths, in: bounds, gap: 5)
        == [0, 25, nil, 72])
    #expect(HistoryChartWindow.dateLabelLefts(centres: [25, 55], widths: [60, 70], in: bounds, gap: 5)
        == [nil, 20])
}

@Test func historySpokenRowListsEveryFact() {
    let row = ScoreHistoryEntry(
        songId: "s", instrument: Instrument.lead.rawValue, newScore: 123_456, accuracy: 985_000, isFullCombo: true,
        season: 4, changedAt: "2024-01-01T00:00:00Z"
    )
    let spoken = SongScoreHistoryChartMath.spokenRow(dateText: "Jan 1, 2024", season: 4, currentSeason: 4, entry: row, isBest: true)
    #expect(spoken == "Jan 1, 2024, current season 4, score 123,456, accuracy 98.5 percent, full combo, best score")
    let plain = SongScoreHistoryChartMath.spokenRow(dateText: "Jan 1, 2024", season: nil, currentSeason: nil, entry: row, isBest: false)
    #expect(!plain.contains("season") && !plain.contains("best"))
}

@Test func historyChartSummaryNamesCountAndBest() {
    let rows = [100, 300, 200].map {
        ScoreHistoryEntry(songId: "s", instrument: Instrument.lead.rawValue, newScore: $0, changedAt: "2024-01-01T00:00:00Z")
    }
    #expect(SongScoreHistoryChartMath.spokenValue(rows) == "3 scores, best 300")
}

// MARK: - Paths activation card

@Test func pathTimeFormatsMinutesSecondsMilliseconds() {
    #expect(SongPathsActivation.time(0) == "00:00:000")
    #expect(SongPathsActivation.time(61.5) == "01:01:500")
    #expect(SongPathsActivation.time(59.9996) == "01:00:000")
}

@Test func pathFretColoursCoverTheFiveLanes() {
    for fret in SongPathsActivation.frets { #expect(SongPathsActivation.fretRGB(fret) != nil) }
    #expect(SongPathsActivation.fretRGB("purple") == nil)
}
