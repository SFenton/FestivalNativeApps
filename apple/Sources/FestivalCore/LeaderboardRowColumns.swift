import Foundation

// MARK: - LeaderboardRowColumns

/// Which leaderboard row columns fit in one section, and how wide the shared ones are,
/// so every row of the section (including a pinned or spotlight row) lines up
/// vertically (issue #37).
///
/// Ported from the web, which decides this once per section:
///
/// - **Visible columns** come from width breakpoints (`packages/theme/src/breakpoints.ts`):
///   season and difficulty from `MEDIUM_BREAKPOINT` (520), stars from
///   `MOBILE_BREAKPOINT` (768), accuracy from `NARROW_BREAKPOINT` (420). The song
///   leaderboard measures the viewport (`LeaderboardPage.tsx` media queries); Song
///   Detail's top-score rows measure their card (`resolveTopScoresColumns`,
///   `pages/songinfo/topScoresLayout.ts`). CSS pixels equal points.
/// - **Rank width** is one value for the section, from the longest `#rank` label
///   (`computeRankWidth`, `pages/leaderboards/helpers/rankingHelpers.ts`: 8.5 px per
///   character plus 12 px), counting the selected player's pinned row.
/// - **Score width** is the longest formatted score in characters (`scoreWidth`
///   `"Nch"` in `LeaderboardPage.tsx`); rankings reserve a rating width
///   (`RankingEntry.tsx` `colRating`).
///
/// Native rendering sizes a column to its section's widest label (``rankLabel``,
/// ``scoreLabel``, ``ratingLabel``) in the row's own font, so widths follow Dynamic
/// Type; ``referenceRankWidth`` keeps the web's pixel formula for cross-platform parity.
///
/// Native decisions (documented in `.agents/controls/leaderboard-row-columns/spec.md`):
/// accuracy is always shown on Apple rows (operator batch 7.8 kept the pills on
/// iPhone, unlike the web's 420/520 px gates), and the rating column uses the
/// section's widest rating rather than reserving `1,000,000,000`, so phone names keep
/// their room.
public struct LeaderboardRowColumns: Sendable, Equatable {
    // MARK: - Surface

    /// The kind of section being laid out; each measures a different width.
    public enum Surface: Sendable, Equatable {
        /// The paginated song (Solo) leaderboard and its pinned row; measured
        /// against the page (viewport) width.
        case songLeaderboard
        /// Song Detail's top-score rows in an instrument card; measured against
        /// the card width. The web card never shows stars.
        case topScores
        /// Account and band rankings (Leaderboards cards, Full/Band Rankings,
        /// Compete): rank, name, songs and rating only.
        case rankings
    }

    // MARK: - Breakpoints

    /// Web `NARROW_BREAKPOINT` / `ACCURACY_BREAKPOINT` (420).
    public static let narrowBreakpoint: Double = 420
    /// Web `MEDIUM_BREAKPOINT` / `SEASON_BREAKPOINT` (520), shared with ``ScoreRowSeasonPolicy``.
    public static let mediumBreakpoint: Double = ScoreRowSeasonPolicy.breakpoint
    /// Web `MOBILE_BREAKPOINT` (768), from which the song leaderboard shows stars.
    public static let wideBreakpoint: Double = 768
    /// Web `Layout.rankCharWidth`: CSS px per rank character at the row font.
    public static let rankCharacterWidth: Double = 8.5
    /// Web `Layout.rankColumnPadding`, added after the rank text.
    public static let rankColumnPadding: Double = 12
    /// Web `Layout.rankColumnWidth`, the rank width of an empty section.
    public static let defaultRankWidth: Double = 48

    // MARK: - Decisions

    /// The section kind these columns were fitted for.
    public var surface: Surface
    /// Show the accuracy badge column.
    public var showsAccuracy: Bool
    /// Show the season pill column before the score.
    public var showsSeason: Bool
    /// Show the difficulty pill column (the web pairs it with the season).
    public var showsDifficulty: Bool
    /// Show the stars column.
    public var showsStars: Bool
    /// The section's widest `#rank` label, or nil when there are no ranks.
    public var rankLabel: String?
    /// The section's widest formatted score, or nil when the section has no scores.
    public var scoreLabel: String?
    /// The section's widest rating label (rankings), or nil.
    public var ratingLabel: String?

    /// Columns with no shared widths and no optional columns except accuracy: rows
    /// size themselves (first-run demos, previews).
    public static let unconstrained = LeaderboardRowColumns(
        surface: .songLeaderboard, showsAccuracy: true, showsSeason: false,
        showsDifficulty: false, showsStars: false,
        rankLabel: nil, scoreLabel: nil, ratingLabel: nil
    )

    /// The web's rank-column width in CSS px (= points at the default text size),
    /// `computeRankWidth`: `ceil(chars × 8.5) + 12`, or 48 for an empty section.
    public var referenceRankWidth: Double {
        guard let rankLabel else { return Self.defaultRankWidth }
        return (Double(rankLabel.count) * Self.rankCharacterWidth).rounded(.up) + Self.rankColumnPadding
    }

    /// The web's score-column width in `ch` (characters of the widest score).
    public var scoreCharacters: Int { max(scoreLabel?.count ?? 0, 1) }

    // MARK: - Fitting

    /// Fit one section's columns.
    ///
    /// - Parameters:
    ///   - surface: The section kind.
    ///   - width: The measured width for `surface` (viewport for
    ///     ``Surface/songLeaderboard``, card for ``Surface/topScores``); zero, negative
    ///     or non-finite (unmeasured) widths fit the narrowest layout.
    ///   - ranks: Every rank shown in the section, including pinned/spotlight rows.
    ///   - scores: Every score shown in the section, including pinned rows.
    ///   - ratings: Every formatted rating label (rankings sections).
    /// - Returns: The visible columns and the widest label per shared column.
    public static func fit(
        _ surface: Surface,
        width: Double,
        ranks: [Int] = [],
        scores: [Int] = [],
        ratings: [String] = []
    ) -> LeaderboardRowColumns {
        let measured = width.isFinite && width > 0 ? width : 0
        let medium = measured >= mediumBreakpoint
        let showsSeason: Bool
        let showsStars: Bool
        switch surface {
        case .songLeaderboard:
            showsSeason = medium
            showsStars = measured >= wideBreakpoint
        case .topScores:
            showsSeason = medium
            showsStars = false
        case .rankings:
            showsSeason = false
            showsStars = false
        }
        return LeaderboardRowColumns(
            surface: surface,
            showsAccuracy: surface != .rankings,
            showsSeason: showsSeason,
            showsDifficulty: showsSeason,
            showsStars: showsStars,
            rankLabel: widest(ranks.filter { $0 > 0 }.map(rankLabel(_:))),
            scoreLabel: widest(scores.filter { $0 >= 0 }.map(scoreLabel(_:))),
            ratingLabel: widest(ratings)
        )
    }

    /// Fit a player-rankings section (Leaderboards cards, Full Rankings, Compete).
    ///
    /// - Parameters:
    ///   - entries: Every row in the section, including a pinned/spotlight row.
    ///   - metric: The rank-by metric whose rank and rating the rows show.
    /// - Returns: Shared rank and rating widths; no score metadata columns.
    public static func rankings(
        _ entries: [AccountRankingEntry], metric: RankingMetric
    ) -> LeaderboardRowColumns {
        fit(
            .rankings, width: 0,
            ranks: entries.map { $0.rank(for: metric) },
            ratings: entries.map { RankingFormatting.rating($0.ratingValue(for: metric), metric: metric) }
        )
    }

    /// Fit a band-rankings section (Leaderboards band cards, Band Rankings).
    ///
    /// - Parameters:
    ///   - entries: Every band row in the section.
    ///   - metric: The band rank-by metric whose rank and rating the rows show.
    /// - Returns: Shared rank and rating widths; no score metadata columns.
    public static func bandRankings(
        _ entries: [BandRankingEntry], metric: BandRankingMetric
    ) -> LeaderboardRowColumns {
        fit(
            .rankings, width: 0,
            ranks: entries.map { $0.rank(for: metric) },
            ratings: entries.map {
                RankingFormatting.rating($0.ratingValue(for: metric), metric: metric.asRankingMetric)
            }
        )
    }

    // MARK: - Labels

    /// A rank as rows draw it: `#` plus the locale-grouped number (web `#{rank.toLocaleString()}`).
    ///
    /// - Parameter rank: 1-based rank.
    /// - Returns: For example `#1,234`.
    public static func rankLabel(_ rank: Int) -> String {
        "#\(rank.formatted())"
    }

    /// A score as rows draw it: the locale-grouped number (web `score.toLocaleString()`).
    ///
    /// - Parameter score: Raw score.
    /// - Returns: For example `709,230`.
    public static func scoreLabel(_ score: Int) -> String {
        score.formatted()
    }

    /// The label with the most characters (the first one on a tie). Same-length
    /// labels of one section share their grouping, so with tabular digits they
    /// render equally wide.
    ///
    /// - Parameter labels: Candidate labels.
    /// - Returns: The longest non-empty label, or nil.
    static func widest(_ labels: [String]) -> String? {
        var best: String?
        for label in labels where !label.isEmpty && label.count > (best?.count ?? 0) {
            best = label
        }
        return best
    }
}
