import Foundation
import FestivalCore

// MARK: - Score History chart maths

/// The Score History chart's pure presentation rules, shared by the SwiftUI chart and the
/// UIKit port's Core Graphics chart: the accuracy colour ramp, date and axis labels, the
/// spoken row and chart summaries, and the score axis ticks.
enum SongScoreHistoryChartMath {
    /// Web `accuracyColor`: red (220, 40, 40) to green (46, 204, 113) over 0 to 100 %.
    ///
    /// - Parameter percent: Accuracy percent.
    /// - Returns: The sRGB components, 0 to 1.
    static func accuracyRGB(_ percent: Double) -> (red: Double, green: Double, blue: Double) {
        let t = min(max(percent / 100, 0), 1)
        return ((220 * (1 - t) + 46 * t) / 255, (40 * (1 - t) + 204 * t) / 255, (40 * (1 - t) + 113 * t) / 255)
    }

    /// Web `dateLabel`: `M/D/YY` in local time.
    ///
    /// - Parameter entry: A history row.
    /// - Returns: The bar's date label, or an em dash without a date.
    static func dateLabel(_ entry: ScoreHistoryEntry) -> String {
        guard let date = entry.displayDate else { return "\u{2014}" }
        let parts = Calendar.current.dateComponents([.month, .day, .year], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)/\(String(parts.year ?? 0).suffix(2))"
    }

    /// A score axis label: thousands abbreviated.
    ///
    /// - Parameter score: Tick value.
    /// - Returns: "12k" or "850".
    static func scoreAxisLabel(_ score: Double) -> String {
        score >= 1000 ? "\(Int((score / 1000).rounded()))k" : "\(Int(score))"
    }

    /// The chart's one-element summary value.
    ///
    /// - Parameter rows: The instrument's rows.
    /// - Returns: "N scores, best X".
    static func spokenValue(_ rows: [ScoreHistoryEntry]) -> String {
        "\(rows.count) scores, best \((rows.map(\.newScore).max() ?? 0).formatted())"
    }

    /// The row below the chart as spoken.
    ///
    /// - Parameters:
    ///   - dateText: The row's date.
    ///   - season: The shown season, if the column is on.
    ///   - currentSeason: The catalogue's current season.
    ///   - entry: The row.
    ///   - isBest: The best score of the list.
    /// - Returns: The row's accessibility label.
    static func spokenRow(dateText: String, season: Int?, currentSeason: Int?, entry: ScoreHistoryEntry, isBest: Bool) -> String {
        "\(dateText)"
            + (season.map { ", " + ScoreSeasonPill.spokenLabel(season: $0, current: $0 == currentSeason).lowercased() } ?? "")
            + ", score \(entry.newScore.formatted())"
            + (entry.accuracy.map { ", accuracy \(ScoreFormatting.accuracy($0)) percent" } ?? "")
            + (entry.isFullCombo == true ? ", full combo" : "")
            + (isBest ? ", best score" : "")
    }

    /// "Nice" tick values for the score axis, about `desiredCount` of them in `0...top`
    /// (the way Swift Charts' automatic axis picks them).
    ///
    /// - Parameters:
    ///   - top: The axis maximum.
    ///   - desiredCount: Target tick count.
    /// - Returns: Ascending tick values starting at 0.
    static func scoreTicks(top: Double, desiredCount: Int = 4) -> [Double] {
        guard top.isFinite, top > 0 else { return [0] }
        let raw = top / Double(max(1, desiredCount - 1))
        let magnitude = pow(10, floor(log10(raw)))
        let step = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * magnitude }.first { $0 >= raw } ?? 10 * magnitude
        return stride(from: 0, through: top, by: step).map { $0 }
    }
}
