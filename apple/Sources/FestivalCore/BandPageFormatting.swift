import Foundation

// MARK: - BandPageFormatting

/// Text rules for the band page, ported from the web's `BandPage.tsx`,
/// `BandSongsSection.tsx` and `BandRankHistoryChart.tsx` (and their `band.*` strings).
public enum BandPageFormatting {
    /// Web `band.rankHistory` window: the page always reads 30 days.
    public static let historyDays = 30

    /// The page title: member names joined with " + " (web `formatBandTitle`), or
    /// "Band" when no name is known.
    ///
    /// - Parameter memberNames: Display names in roster order.
    /// - Returns: For example "SFentonX + Player Two".
    public static func title(memberNames: [String]) -> String {
        let names = memberNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return names.isEmpty ? "Band" : names.joined(separator: " + ")
    }

    /// The line under the title (web `band.subtitle`, "{{type}} • {{count}} appearances"),
    /// with a singular for one appearance.
    ///
    /// - Parameters:
    ///   - bandType: The band's size.
    ///   - appearances: Songs the band appears on (the ranking's `songsPlayed`).
    /// - Returns: For example "Duos • 142 appearances".
    public static func subtitle(bandType: BandType, appearances: Int) -> String {
        let count = max(0, appearances)
        return "\(bandType.label) • \(count.formatted()) \(count == 1 ? "appearance" : "appearances")"
    }

    /// Web `formatRank`: "#1,234", or an em dash when unranked.
    ///
    /// - Parameter rank: 1-based rank; 0 or less is unranked.
    /// - Returns: The tile value.
    public static func rank(_ rank: Int) -> String {
        rank > 0 ? "#\(rank.formatted())" : "—"
    }

    /// Web `formatAverageRank`: "#12.3", or an em dash.
    ///
    /// - Parameter rank: Mean rank across the band's songs.
    /// - Returns: The tile value.
    public static func averageRank(_ rank: Double) -> String {
        guard rank.isFinite, rank > 0 else { return "—" }
        return "#\(rank.formatted(.number.precision(.fractionLength(1))))"
    }

    /// Web `formatAccuracy`: one decimal percent, or an em dash.
    ///
    /// - Parameter accuracy: Mean accuracy in ten-thousandths of a percent (`ACCURACY_SCALE`).
    /// - Returns: For example "98.8%".
    public static func accuracy(_ accuracy: Double) -> String {
        guard accuracy.isFinite, accuracy > 0 else { return "—" }
        return "\((accuracy / 10_000).formatted(.number.precision(.fractionLength(1))))%"
    }

    /// Web `formatStars` for anything but six (which draws gold stars): one decimal, or
    /// an em dash.
    ///
    /// - Parameter stars: Mean stars across played songs.
    /// - Returns: The tile value.
    public static func stars(_ stars: Double) -> String {
        guard stars.isFinite, stars > 0 else { return "—" }
        return stars.formatted(.number.precision(.fractionLength(1)))
    }

    /// Whether the average-stars tile draws gold stars (web `stars === 6`).
    ///
    /// - Parameter stars: Mean stars across played songs.
    /// - Returns: True at six.
    public static func isGoldStars(_ stars: Double) -> Bool { stars >= 6 }

    /// Web FC Rate tile: `(fcRate * 100).toFixed(1)%`.
    ///
    /// - Parameter fraction: Full-combo fraction, 0–1.
    /// - Returns: For example "12.5%".
    public static func fcRate(_ fraction: Double) -> String {
        RankingFormatting.percentage(fraction)
    }

    /// "x / total" for Songs Played and Full Combos.
    ///
    /// - Parameters:
    ///   - count: Songs played or full-combo count.
    ///   - total: Charted songs.
    /// - Returns: For example "120 / 640".
    public static func ofTotal(_ count: Int, _ total: Int) -> String {
        "\(count.formatted()) / \(total.formatted())"
    }

    /// The Rank History subtitle: the web's hint plus its history-status suffix
    /// (`BandRankHistoryChart.statusMessage`). A service message wins over the built-in
    /// text; `failed` adds nothing.
    ///
    /// - Parameters:
    ///   - days: History window.
    ///   - status: `historyStatus` (`current`, `catching_up`, `stale`, `failed`, `disabled`).
    ///   - message: `historyMessage`, if the service sent one.
    /// - Returns: The subtitle sentence(s).
    public static func historySubtitle(days: Int, status: String?, message: String?) -> String {
        let base = "Any-combo ranking progression over the past \(days) days."
        guard status != "failed" else { return base }
        let suffix: String? = if let message, !message.isEmpty {
            message
        } else {
            switch status {
            case "catching_up": "History is catching up. Current rankings are already fresh."
            case "stale": "Rank history is behind the latest current rankings."
            case "disabled": "Rank history is disabled while current rankings remain available."
            default: nil
            }
        }
        return suffix.map { "\(base) \($0)" } ?? base
    }

    /// Five Best Songs description (web `band.bestSongsDesc`).
    ///
    /// - Parameter name: The page title.
    /// - Returns: The section description.
    public static func bestSongsDescription(_ name: String) -> String {
        "\(name)'s highest-ranked band songs, sorted by percentile."
    }

    /// Five Worst Songs description (web `band.worstSongsDesc`).
    ///
    /// - Parameter name: The page title.
    /// - Returns: The section description.
    public static func worstSongsDescription(_ name: String) -> String {
        "\(name)'s lowest-ranked band songs, sorted by percentile."
    }
}

// MARK: - RankHistoryValueKind

/// What a rank-history chart's bars measure, and how to write their values: the
/// Player profile's Total Score, or a band's Rank By metric (web
/// `rankHistoryChartModel.formatValueTick` and `rankings.metric.*` labels).
public enum RankHistoryValueKind: Equatable, Sendable {
    /// A player's per-instrument Total Score history.
    case playerTotalScore
    /// A band's history at a Rank By metric.
    case band(BandRankingMetric)

    /// Axis title, legend label and bar series name (web `rankings.metric.*`).
    public var title: String {
        switch self {
        case .playerTotalScore, .band(.totalscore): "Total Score"
        case .band(.adjusted): "Adjusted Percentile"
        case .band(.weighted): "Popularity-Weighted Percentile"
        case .band(.fcrate): "FC Rate"
        }
    }

    /// The rank the line plots, as VoiceOver names it.
    public var rankName: String {
        switch self {
        case .playerTotalScore: "global rank"
        case .band: "band rank"
        }
    }

    /// The Audio Graph rank series name: "Total Score rank", "FC Rate rank", ….
    public var rankSeriesName: String { "\(title) rank" }

    /// The value in sentence case, keeping acronyms: "Total score", "FC rate".
    public var sentenceName: String { inlineName.prefix(1).uppercased() + inlineName.dropFirst() }

    /// The value mid-sentence, keeping acronyms: "total score", "FC rate".
    public var inlineName: String {
        title.split(separator: " ").map { word in
            word.count > 1 && word == word.uppercased() ? String(word) : word.lowercased()
        }.joined(separator: " ")
    }

    /// A value-axis tick (web `formatValueTick`): percent for FC Rate, compact for
    /// Total Score, two decimals for the percentile ratings.
    ///
    /// - Parameter value: Axis value.
    /// - Returns: Tick text.
    public func tick(_ value: Double) -> String {
        switch self {
        case .playerTotalScore, .band(.totalscore):
            RankHistoryChartFormat.compactScore(value)
        case .band(.fcrate):
            "\(Int((value * 100).rounded()))%"
        case .band(.adjusted), .band(.weighted):
            String(format: "%.2f", value)
        }
    }

    /// A readable value for summaries and VoiceOver, as Band Rankings rows write it.
    ///
    /// - Parameter value: Snapshot value.
    /// - Returns: For example "89,400,000", "Top 3%" or "12.5%".
    public func text(_ value: Double) -> String {
        switch self {
        case .playerTotalScore: Int(value).formatted()
        case let .band(metric): RankingFormatting.rating(value, metric: metric.asRankingMetric)
        }
    }
}
