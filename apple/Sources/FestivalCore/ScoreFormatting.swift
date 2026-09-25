import Foundation

/// Shared service-score display policy for native solo leaderboard rows.
public enum ScoreFormatting {
    /// Display expanded accuracy as a percent with one digit only when needed.
    ///
    /// - Parameter expandedAccuracy: Service accuracy measured in ten-thousandths of a percent.
    /// - Returns: User-locale percent number, without the percent sign.
    public static func accuracy(_ expandedAccuracy: Double) -> String {
        let rounded = (expandedAccuracy / 1_000).rounded() / 10
        let fractionDigits = rounded == rounded.rounded() ? 0 : 1
        return rounded.formatted(.number.precision(.fractionLength(fractionDigits)))
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
}
