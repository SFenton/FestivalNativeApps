import Foundation

/// Shared service-score display policy for native solo leaderboard rows.
public enum ScoreFormatting {
    private static let percentileBuckets = [
        1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100
    ]

    /// Display expanded accuracy as a percent with one digit only when needed.
    ///
    /// - Parameter expandedAccuracy: Service accuracy measured in ten-thousandths of a percent.
    /// - Returns: User-locale percent number, without the percent sign.
    public static func accuracy(_ expandedAccuracy: Double) -> String {
        let rounded = (expandedAccuracy / 1_000).rounded() / 10
        let fractionDigits = rounded == rounded.rounded() ? 0 : 1
        return rounded.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// Match the source's red-to-green accuracy-pill background at 25% opacity.
    ///
    /// - Parameter expandedAccuracy: Service accuracy in ten-thousandths of a percent.
    /// - Returns: Rounded sRGB components; the caller applies 25% opacity.
    /// - Throws: `FestivalAPIError.invalidLeaderboard` for nonfinite score data.
    public static func accuracyTint(_ expandedAccuracy: Double) throws -> ScoreAccuracyTint {
        guard expandedAccuracy.isFinite else {
            throw FestivalAPIError.invalidLeaderboard
        }
        let fraction = min(max(expandedAccuracy / 1_000_000, 0), 1)
        return ScoreAccuracyTint(
            red: Int((220 * (1 - fraction) + 46 * fraction).rounded()),
            green: Int((40 * (1 - fraction) + 204 * fraction).rounded()),
            blue: Int((40 * (1 - fraction) + 113 * fraction).rounded())
        )
    }

    /// Present a signed leeway value without turning zero into a positive offset.
    ///
    /// - Parameter value: Current percentage tolerance in Settings.
    /// - Returns: A value such as `+1.0%`, `0.0%`, or `-0.5%`.
    public static func leeway(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded.formatted(.number.precision(.fractionLength(1)))
        return "\(rounded > 0 ? "+" : "")\(text)%"
    }

    /// Bucket a selected song score's rank as the source Songs row does.
    ///
    /// - Parameters:
    ///   - rank: One-based position in the published song chart.
    ///   - totalEntries: Positive published chart population.
    /// - Returns: The first source bucket at or above the clamped percentile, or nil for no rank.
    public static func percentileBucket(rank: Int, totalEntries: Int) -> String? {
        guard rank > 0, totalEntries > 0 else { return nil }
        return percentileBucket(percentile: Double(rank) / Double(totalEntries) * 100)
    }

    /// Bucket a 0–100 percentile as the web's `formatPercentileBucket` does (band
    /// Five Best/Worst Songs rows).
    ///
    /// - Parameter percentile: Rank as a percent of the chart population (lower is better).
    /// - Returns: "Top N%" for the first bucket at or above the value clamped to 1–100,
    ///   or nil for a non-finite input.
    public static func percentileBucket(percentile: Double) -> String? {
        guard percentile.isFinite else { return nil }
        let clamped = min(max(percentile, 1), 100)
        let bucket = percentileBuckets.first { clamped <= Double($0) } ?? 100
        return "Top \(bucket)%"
    }
}

/// Pure color components for a graded, non-full-combo accuracy pill.
public struct ScoreAccuracyTint: Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int
}
