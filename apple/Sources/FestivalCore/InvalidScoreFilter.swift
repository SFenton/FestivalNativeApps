import Foundation

// MARK: - Invalid-score filter

/// Settings' **Filter Invalid Scores** policy (`SettingsPage.tsx` "Filter Invalid Scores" +
/// "Maximum Score Leeway"): when on, leaderboard reads carry a `leeway` percentage and the
/// service drops entries above `maxScore × (1 + leeway / 100)`.
///
/// Verified on production 2026-09-28 (Lane AP4): Winterfest Wish Lead (`Solo_Guitar`, CHOpt
/// max 81,996) lists 10,009 local entries unfiltered but only 7 with `leeway=1.0`, whose top
/// score drops from 100,955 to 79,243.
public enum InvalidScoreFilter {
    /// Slider bounds (web `LeewaySlider`: −5 % … +5 %).
    public static let range: ClosedRange<Double> = -5...5
    /// Slider step (0.1 %).
    public static let step: Double = 0.1
    /// Default leeway (+1 %).
    public static let defaultLeeway: Double = 1
    /// The web's example CHOpt maximum used in the leeway description ("a CHOpt path with
    /// a max score of 100k").
    public static let exampleMaxScore = 100_000

    /// Snap a raw slider value to the persisted leeway: one decimal, within ``range``.
    ///
    /// - Parameter raw: Slider or stored value.
    /// - Returns: Clamped value rounded to the 0.1 % step; the default for non-finite input.
    public static func normalized(_ raw: Double) -> Double {
        guard raw.isFinite else { return defaultLeeway }
        let snapped = (raw * 10).rounded() / 10
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    /// The `leeway` query value a leaderboard read should send.
    ///
    /// - Parameters:
    ///   - enabled: Filter Invalid Scores switch.
    ///   - leeway: Stored leeway percentage.
    /// - Returns: The normalized leeway when filtering, otherwise nil (no query item).
    public static func queryLeeway(enabled: Bool, leeway: Double) -> Double? {
        enabled ? normalized(leeway) : nil
    }

    /// Highest score still accepted as valid for a chart.
    ///
    /// - Parameters:
    ///   - maxScore: CHOpt maximum for the chart.
    ///   - leeway: Leeway percentage.
    /// - Returns: `maxScore × (1 + leeway / 100)`, rounded to a whole score.
    public static func ceiling(maxScore: Int, leeway: Double) -> Int {
        Int((Double(maxScore) * (1 + normalized(leeway) / 100)).rounded())
    }

    /// Whether a score survives the filter.
    ///
    /// - Parameters:
    ///   - score: Leaderboard score.
    ///   - maxScore: CHOpt maximum for the chart, or nil when unknown.
    ///   - leeway: Leeway percentage.
    /// - Returns: True when the score is at or under the ceiling, or when no maximum is known
    ///   (an unknown maximum can't prove a score invalid).
    public static func isValid(score: Int, maxScore: Int?, leeway: Double) -> Bool {
        guard let maxScore, maxScore > 0 else { return true }
        return score <= ceiling(maxScore: maxScore, leeway: leeway)
    }

    /// Count the scores a filter would drop.
    ///
    /// - Parameters:
    ///   - scores: Leaderboard scores.
    ///   - maxScore: CHOpt maximum for the chart.
    ///   - leeway: Leeway percentage.
    /// - Returns: Number of scores above the ceiling.
    public static func invalidCount(_ scores: [Int], maxScore: Int?, leeway: Double) -> Int {
        scores.filter { !isValid(score: $0, maxScore: maxScore, leeway: leeway) }.count
    }
}
