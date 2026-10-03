import Foundation

// MARK: - Shared ISO-8601 parsing

/// Reused ISO-8601 formatters for service timestamps.
///
/// Creating an `ISO8601DateFormatter` costs far more than parsing with one (on the
/// Mac, Song Detail's score-history chart created two per entry on every body
/// evaluation, which showed up in Songs scroll-stress profiles). Foundation's
/// formatters are thread-safe for parsing once configured, and these are never
/// reconfigured after creation.
public enum ISO8601Parsing {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let whole = ISO8601DateFormatter()

    /// Parse an internet date-time with or without fractional seconds.
    ///
    /// - Parameter text: Timestamp text.
    /// - Returns: The date, or nil when neither form parses.
    public static func date(_ text: String) -> Date? {
        fractional.date(from: text) ?? whole.date(from: text)
    }

    /// Parse an internet date-time without fractional seconds.
    ///
    /// - Parameter text: Timestamp text.
    /// - Returns: The date, or nil when it does not parse.
    public static func wholeSecondsDate(_ text: String) -> Date? {
        whole.date(from: text)
    }
}
