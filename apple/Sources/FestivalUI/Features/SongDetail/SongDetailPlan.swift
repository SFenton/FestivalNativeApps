import Foundation
import FestivalCore

// MARK: - Song Detail plan

/// The page's pure decisions, shared by the SwiftUI ``SongDetailScreen`` and the UIKit port:
/// which charts are listed, which have paths, the Quick Links order and the card captions.
enum SongDetailPlan {
    /// Every chart the song supports, in `Instrument` order.
    ///
    /// - Parameter song: The catalogue record.
    /// - Returns: The charted instruments.
    static func charted(_ song: Song) -> [Instrument] {
        Instrument.allCases.filter(song.supports)
    }

    /// Charts that get a leaderboard preview card: charted and enabled in Settings.
    ///
    /// - Parameters:
    ///   - song: The catalogue record.
    ///   - visible: Instruments Settings shows.
    /// - Returns: The cards' instruments in page order.
    static func previewInstruments(_ song: Song, visible: Set<Instrument>) -> [Instrument] {
        charted(song).filter(visible.contains)
    }

    /// Visible instruments the Paths sheet offers (Karaoke has no path).
    ///
    /// - Parameter visible: Instruments Settings shows.
    /// - Returns: The sheet's instruments in `Instrument` order.
    static func pathInstruments(visible: Set<Instrument>) -> [Instrument] {
        Instrument.allCases.filter { $0 != .karaoke && visible.contains($0) }
    }

    /// Quick Links entry for one band-size preview section (web id `band-<bandType>`).
    ///
    /// - Parameter bandType: Band size.
    /// - Returns: The section's menu entry.
    static func bandQuickLink(_ bandType: BandType) -> QuickLinkSection {
        QuickLinkSection(id: "band-\(bandType.rawValue)", title: bandType.label, icon: .system(bandType.symbolName))
    }

    /// Intensity, Score History (when shown), one entry per visible card, then the band
    /// sections: the page's top-to-bottom order (`.agents/controls/quick-links/ios.md`).
    ///
    /// - Parameters:
    ///   - previewInstruments: The cards' instruments.
    ///   - showsScoreHistory: Whether Score History is drawn.
    /// - Returns: The Quick Links sections.
    static func quickLinkSections(previewInstruments: [Instrument], showsScoreHistory: Bool) -> [QuickLinkSection] {
        [QuickLinkSection(id: "intensity", title: "Intensity", icon: .system("chart.bar.fill"))]
            + (showsScoreHistory ? [
                QuickLinkSection(id: "score-history", title: "Score History", icon: .system("chart.line.uptrend.xyaxis")),
            ] : [])
            + previewInstruments.map { instrument in
                QuickLinkSection(id: "instrument-\(instrument.rawValue)", title: instrument.label, icon: .instrument(instrument))
            }
            + BandType.allCases.map(bandQuickLink)
    }

    /// Total entries for a loaded chart, the card header's subtitle when the service
    /// asks for totals.
    ///
    /// - Parameter payload: The chart's first page.
    /// - Returns: "No scores recorded yet", "N entries", or nil.
    static func entriesSubtitle(_ payload: LeaderboardPayload) -> String? {
        if payload.leaderboard.entries.isEmpty { return "No scores recorded yet" }
        guard payload.leaderboard.showLeaderboardEntryTotals == true else { return nil }
        let total = payload.leaderboard.totalEntries
        return "\(total.formatted()) \(total == 1 ? "entry" : "entries")"
    }

    /// Total ranked bands, a band card header's subtitle when the service allows it.
    ///
    /// - Parameters:
    ///   - response: The one band read.
    ///   - bandType: Band size.
    /// - Returns: "No scores recorded yet", "N bands", or nil.
    static func bandSubtitle(_ response: SongBandLeaderboardsResponse, bandType: BandType) -> String? {
        let preview = response.preview(for: bandType)
        if preview.entries.isEmpty && preview.footerEntry == nil { return "No scores recorded yet" }
        guard response.showLeaderboardEntryTotals == true else { return nil }
        let total = preview.totalEntries
        return "\(total.formatted()) \(total == 1 ? "band" : "bands")"
    }
}
