import Foundation

// MARK: - PlayerStarBreakdown

/// One instrument's star distribution and average, mirroring the web's
/// `computeInstrumentStats` star counts (`pages/player/helpers/playerStats.ts`), computed
/// only from the compact public `scores` array.
public struct PlayerStarBreakdown: Equatable, Sendable {
    /// Scores with six stars (gold).
    public let gold: Int
    /// Scores with exactly five stars.
    public let five: Int
    /// Scores with exactly four stars.
    public let four: Int
    /// Scores with exactly three stars.
    public let three: Int
    /// Scores with exactly two stars.
    public let two: Int
    /// Scores with exactly one star.
    public let one: Int
    /// Mean stars over scores with at least one star; 0 when none (web `averageStars`).
    public let average: Double

    /// Whether every starred score is gold, which the web shows as five gold stars.
    public var isAllGold: Bool { average == 6 }

    /// The web's `formatClamped2`: two decimals with trailing zeros removed, or an em
    /// dash when nothing has stars.
    public var averageText: String {
        guard average > 0 else { return "\u{2014}" }
        var text = String(format: "%.2f", (average * 100).rounded() / 100)
        if text.hasSuffix("00") { text.removeLast(3) } else if text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// Count cards the web shows after Full Combos, best first, each only when non-zero.
    ///
    /// - Returns: `(label, stars, count)` rows: Gold Stars (6), 5 Stars … 1 Star.
    public var countCards: [(label: String, stars: Int, count: Int)] {
        [
            ("Gold Stars", 6, gold), ("5 Stars", 5, five), ("4 Stars", 4, four),
            ("3 Stars", 3, three), ("2 Stars", 2, two), ("1 Star", 1, one),
        ].filter { $0.2 > 0 }
    }
}

extension PlayerProfileResponse {
    /// Star distribution for one instrument's scores.
    ///
    /// - Parameter instrument: Solo chart to summarize.
    /// - Returns: Zeroed counts for an unplayed chart.
    public func starBreakdown(_ instrument: Instrument) -> PlayerStarBreakdown {
        let stars = scores.filter { $0.instrument == instrument }.map { $0.stars ?? 0 }
        let starred = stars.filter { $0 > 0 }
        return PlayerStarBreakdown(
            gold: stars.filter { $0 >= 6 }.count,
            five: stars.filter { $0 == 5 }.count,
            four: stars.filter { $0 == 4 }.count,
            three: stars.filter { $0 == 3 }.count,
            two: stars.filter { $0 == 2 }.count,
            one: stars.filter { $0 == 1 }.count,
            average: starred.isEmpty ? 0 : Double(starred.reduce(0, +)) / Double(starred.count)
        )
    }
}
