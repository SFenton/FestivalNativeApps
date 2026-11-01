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
