import Foundation
import FestivalCore

// MARK: - Row presentation

/// What the selected profile puts under a Songs row's title.
enum SongRowProfileContent {
    /// Nothing (anonymous, or a band with nothing to show).
    case none
    /// "Player scores paused until songs update".
    case pausedPlayer
    /// Per-chart status chips.
    case chips([SongInstrumentBadge])
    /// The one-line selected-chart summary (``SongProfileSummary``).
    case summary(player: SelectedPlayerIdentity, chart: Instrument?, chartAvailable: Bool, score: PlayerScore?, state: SelectedPlayerLoadState)
    /// "Loading <band>'s scores".
    case bandLoading(String)
    /// "Band scores unavailable".
    case bandFailed
    /// "Band scores paused until songs update".
    case bandPaused
    /// The band's score pills.
    case bandFields([SongMetadataField])
}

/// The decisions behind one Songs row (``SongRowView``): which score data applies, which
/// profile content shows and what the indicator says. Shared by the SwiftUI row and the
/// UIKit port, so both read the same score-index provenance rules.
@MainActor
struct SongRowPresentation {
    let song: Song
    let instrument: Instrument?
    let session: FestivalSession
    let profileChart: Instrument?
    let catalogueObservation: Int?
    let metadata: SongMetadataVisibility
    let invalidScoreLeeway: Double?
    let overThresholdCharts: Set<Instrument>
    let showInstrumentIcons: Bool
    let visibleInstruments: Set<Instrument>
    let currentSeason: Int?
    let isShopRow: Bool
    /// Score-field order (``MetadataField/songRowOrder(independent:saved:)``).
    let fieldOrder: [MetadataField]

    /// The selected player's score index is available and matches these Songs rows.
    var scoreDataCurrent: Bool { session.hasCurrentPlayerScores(forCatalogue: catalogueObservation) }

    /// The selected band's index is available and matches these Songs rows.
    var bandScoreDataCurrent: Bool { session.hasCurrentBandScores(forCatalogue: catalogueObservation) }

    /// The selected band's fields for this song on a plain row, or nil without a current,
    /// positive band score.
    var bandFields: [SongMetadataField]? {
        guard session.selectedBand != nil, bandScoreDataCurrent,
              let entry = session.selectedBandScores[song.songId], entry.score > 0,
              let fields = try? SongProfileCardPolicy.bandFields(
                  for: entry, currentSeason: currentSeason, visibility: metadata
              ), !fields.isEmpty else { return nil }
        return SongProfileCardPolicy.reordered(fields, by: fieldOrder)
    }

    /// Whether the row shows per-chart status chips instead of score text.
    var usesInstrumentChips: Bool {
        SongInstrumentStatusPolicy.showsChips(
            hasSelectedPlayer: session.selectedPlayer != nil, scoresAvailable: scoreDataCurrent,
            iconsEnabled: showInstrumentIcons, instrumentFilter: instrument, visibleInstruments: visibleInstruments
        )
    }

    /// The selected player's scores for this song as the row shows them: raw, or with
    /// Filter Invalid Scores applied.
    var playerScores: SongEffectiveScores {
        let raw = session.selectedPlayerScores[song.songId] ?? [:]
        guard let invalidScoreLeeway, !raw.isEmpty else { return SongEffectiveScores(scores: raw) }
        return InvalidScorePolicy.resolve(raw, song: song, leeway: invalidScoreLeeway, overThreshold: overThresholdCharts)
    }

    /// The invalid-score indicator's tone and alert, only for a selected player's current
    /// scores on a Songs row.
    var invalidScoreWarning: InvalidScoreWarning? {
        guard invalidScoreLeeway != nil, !isShopRow, session.selectedPlayer != nil,
              session.selectedBand == nil, scoreDataCurrent else { return nil }
        return InvalidScoreWarning.make(
            songTitle: song.title, reasons: playerScores.reasons,
            instrumentFilter: instrument, visibleInstruments: visibleInstruments
        )
    }

    /// The selected chart's positive score, when the row shows score metadata.
    var structuredScore: (chart: Instrument, score: PlayerScore)? {
        guard !usesInstrumentChips, scoreDataCurrent, let chart = profileChart, song.supports(chart),
              let score = playerScores.scores[chart], score.score > 0 else { return nil }
        return (chart, score)
    }

    /// The structured score's ordered fields (or the projection's failure).
    var structuredFields: Result<[SongMetadataField], Error>? {
        guard let structuredScore else { return nil }
        return Result {
            let fields = try SongProfileCardPolicy.fields(
                for: structuredScore.score, chart: structuredScore.chart,
                song: song, currentSeason: currentSeason, visibility: metadata
            )
            return SongProfileCardPolicy.reordered(fields, by: fieldOrder)
        }
    }

    /// "artist · year · duration".
    var subtitle: String {
        var subtitle = song.artist
        if let year = song.year, year != 0 { subtitle += " · \(year)" }
        if let duration = song.formattedDuration { subtitle += " · \(duration)" }
        return subtitle
    }

    /// What goes under the title for the selected player or band.
    var profileContent: SongRowProfileContent {
        if let selected = session.selectedPlayer {
            if session.playerLoadState == .available && !scoreDataCurrent { return .pausedPlayer }
            if usesInstrumentChips {
                return .chips(SongInstrumentStatusPolicy.badges(
                    for: song, visibleInstruments: visibleInstruments, scores: playerScores.scores
                ))
            }
            return .summary(
                player: selected, chart: profileChart, chartAvailable: profileChart.map(song.supports) ?? false,
                score: scoreDataCurrent ? profileChart.flatMap { playerScores.scores[$0] } : nil,
                state: session.playerLoadState
            )
        }
        if let band = session.selectedBand {
            switch session.bandLoadState {
            case .loading: return .bandLoading(band.displayName)
            case .failed: return .bandFailed
            case .available where !bandScoreDataCurrent: return .bandPaused
            case .available, .none, .syncing:
                if let bandFields { return .bandFields(bandFields) }
                return .none
            }
        }
        return .none
    }
}

// MARK: - Summary text

/// The words of ``SongProfileSummary`` as plain values, so the UIKit row says the same.
enum SongProfileSummaryText {
    /// One summary line.
    struct Line: Equatable {
        let text: String
        /// Gold (a warning) instead of white.
        let gold: Bool
        /// SF Symbol name when the line is a status label.
        let symbol: String?
    }

    /// The line for a player's state on a row.
    ///
    /// - Parameters:
    ///   - player: The selected player.
    ///   - chart: The row's chart.
    ///   - chartAvailable: The song charts it.
    ///   - score: The effective score, nil when absent or paused.
    ///   - state: The player's load state.
    ///   - visibility: Saved score-field switches.
    /// - Returns: The text to show.
    static func line(
        player: SelectedPlayerIdentity, chart: Instrument?, chartAvailable: Bool, score: PlayerScore?,
        state: SelectedPlayerLoadState, visibility: SongMetadataVisibility
    ) -> Line {
        switch state {
        case .none:
            return Line(text: "Selected player scores are not loaded", gold: true, symbol: nil)
        case .loading:
            return Line(text: "Loading \(player.displayName)'s scores", gold: false, symbol: "hourglass")
        case .syncing:
            return Line(text: "Player scores are syncing", gold: false, symbol: "arrow.triangle.2.circlepath")
        case .failed:
            return Line(text: "Player scores unavailable", gold: true, symbol: "exclamationmark.triangle")
        case .available:
            if let chart, !chartAvailable {
                return Line(text: "\(chart.label) is not charted for this song", gold: false, symbol: nil)
            } else if let chart, let score, score.score > 0 {
                do {
                    let values = try SongProfileCardPolicy.labels(for: score, chart: chart, visibility: visibility)
                    return Line(text: values.joined(separator: " · "), gold: false, symbol: nil)
                } catch {
                    return Line(text: "Player score metadata unavailable: \(error.localizedDescription)", gold: true, symbol: nil)
                }
            } else if let chart {
                return Line(text: "No \(chart.label) score for \(player.displayName)", gold: false, symbol: nil)
            } else {
                return Line(text: "No visible instrument in Settings", gold: true, symbol: nil)
            }
        }
    }
}
