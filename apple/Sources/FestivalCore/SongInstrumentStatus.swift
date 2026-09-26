import Foundation

/// One source-backed Songs chip status with a separately announced inconsistent state.
public enum SongInstrumentStatus: Equatable, Sendable {
    case unavailable
    case fullCombo
    case scored
    case noScore
    case inconsistentFullCombo

    /// Describe status without relying on the chip's fill or decorative mark.
    ///
    /// - Returns: Localized-ready status words for a row's spoken summary.
    public var announcement: String {
        switch self {
        case .unavailable: "not charted"
        case .fullCombo: "full combo"
        case .scored: "scored"
        case .noScore: "no score"
        case .inconsistentFullCombo: "score missing despite a reported full combo"
        }
    }
}

/// Bounded per-instrument status independent of presentation, artwork or network.
public struct SongInstrumentBadge: Identifiable, Equatable, Sendable {
    public let instrument: Instrument
    public let status: SongInstrumentStatus

    public var id: Instrument { instrument }

    /// Include the instrument name in every chip's accessibility announcement.
    ///
    /// - Returns: One unambiguous chart and status phrase.
    public var announcement: String {
        "\(instrument.label), \(status.announcement)"
    }
}

/// Derive statuses from the selected account's already validated process-only index.
public enum SongInstrumentStatusPolicy {
    /// Gate chips without interpreting a syncing or failed profile as no scores.
    ///
    /// - Parameters:
    ///   - hasSelectedPlayer: Identity explicitly chosen by the user.
    ///   - scoresAvailable: Published, identity-matched HTTP 200 profile loaded.
    ///   - iconsEnabled: Saved Show Instrument Icons setting.
    ///   - instrumentFilter: An explicit single chart, or nil for all instruments.
    ///   - filterInvalidScores: Unsupported precomputed-score fallback still requested.
    ///   - visibleInstruments: User-enabled charts, at least one in normal Settings.
    /// - Returns: True only for the selected, available, unfiltered icon presentation.
    public static func showsChips(
        hasSelectedPlayer: Bool, scoresAvailable: Bool, iconsEnabled: Bool,
        instrumentFilter: Instrument?, filterInvalidScores: Bool,
        visibleInstruments: Set<Instrument>
    ) -> Bool {
        hasSelectedPlayer && scoresAvailable && iconsEnabled
            && instrumentFilter == nil && !filterInvalidScores
            && !visibleInstruments.isEmpty
    }

    /// Resolve each enabled chart once in the source's stable nine-instrument order.
    ///
    /// - Parameters:
    ///   - song: Current validated catalogue row and its independent chart support.
    ///   - visibleInstruments: Saved enabled charts.
    ///   - scores: This one song's verified instrument index, not the whole profile.
    /// - Returns: At most nine source-ordered statuses, with no inferred FC or score.
    public static func badges(
        for song: Song, visibleInstruments: Set<Instrument>,
        scores: [Instrument: PlayerScore]
    ) -> [SongInstrumentBadge] {
        Instrument.allCases.filter(visibleInstruments.contains).map { instrument in
            let status: SongInstrumentStatus
            if !song.supports(instrument) {
                status = .unavailable
            } else if let score = scores[instrument] {
                if score.score > 0 {
                    status = score.isFullCombo == true ? .fullCombo : .scored
                } else {
                    status = score.isFullCombo == true ? .inconsistentFullCombo : .noScore
                }
            } else {
                status = .noScore
            }
            return SongInstrumentBadge(instrument: instrument, status: status)
        }
    }
}
