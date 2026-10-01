import Foundation
import FestivalCore

// MARK: - Shared static sample data

/// Static sample data shared by the non-Songs first-run demos, mirroring the shape of the web's
/// `firstRun/demoData.ts` (hand-picked player names, ranks and scores). Song titles and artwork
/// never come from here: song demos use real catalogue songs via `FirstRunCatalogueSongs` — see
/// `.agents/controls/first-run/ios.md`.
enum FirstRunDemoPool {
    // MARK: Rankings

    /// One leaderboard row, matching the web's `DemoRankingEntry`.
    struct RankingEntry: Identifiable, Hashable {
        let rank: Int
        let name: String
        let rating: String
        var isPlayer: Bool = false
        var id: Int { rank }
        /// Songs column ("played/total"), like the real rankings row.
        var songs: String { "\(max(120, 512 - rank * 3))/512" }
    }

    static let rankings: [RankingEntry] = [
        .init(rank: 1, name: "GoldStreak", rating: "2,480,000"),
        .init(rank: 2, name: "NoteHunter", rating: "2,310,500"),
        .init(rank: 3, name: "BeatLegend", rating: "2,275,100"),
        .init(rank: 4, name: "VocalStorm", rating: "2,198,000"),
        .init(rank: 5, name: "BassRuler", rating: "2,112,800"),
        .init(rank: 6, name: "TopClutch", rating: "2,045,300"),
        .init(rank: 7, name: "StageKnight", rating: "1,998,700"),
        .init(rank: 8, name: "RhythmEdge", rating: "1,922,400"),
    ]

    /// Rows surrounding the player (ranks 39-45), matching the web's `DEMO_NEIGHBORHOOD`.
    static let rankingNeighborhood: [RankingEntry] = [
        .init(rank: 39, name: "SonicRush", rating: "1,278,400"),
        .init(rank: 40, name: "DeepGroove", rating: "1,265,100"),
        .init(rank: 41, name: "KeyDrifter", rating: "1,258,000"),
        .init(rank: 42, name: "You", rating: "1,250,000", isPlayer: true),
        .init(rank: 43, name: "DrumSurge", rating: "1,241,300"),
        .init(rank: 44, name: "ShredLord", rating: "1,230,800"),
        .init(rank: 45, name: "NoteCrush", rating: "1,219,500"),
    ]

    // MARK: Rivals

    /// One rival summary row, matching the web's `RivalSummary` shape.
    struct RivalEntry: Identifiable, Hashable, RivalRowDisplayable {
        let id = UUID()
        let name: String
        let shared: Int
        let ahead: Int
        let behind: Int

        // `RivalRowDisplayable`, so demos render the real `RivalRowContent`. That row's
        // "ahead" pill reads `behindCount` (songs the rival is behind the player on).
        var accountId: String { "fre-\(name)" }
        var displayName: String? { name }
        var sharedSongCount: Int { shared }
        var behindCount: Int { ahead }
        var aheadCount: Int { behind }
    }

    static let rivalsAbove: [RivalEntry] = [
        .init(name: "KeyDrifter", shared: 148, ahead: 82, behind: 66),
        .init(name: "DeepGroove", shared: 135, ahead: 75, behind: 60),
        .init(name: "SonicRush", shared: 120, ahead: 68, behind: 52),
    ]

    static let rivalsBelow: [RivalEntry] = [
        .init(name: "DrumSurge", shared: 142, ahead: 58, behind: 84),
        .init(name: "ShredLord", shared: 130, ahead: 50, behind: 80),
        .init(name: "NoteCrush", shared: 118, ahead: 44, behind: 74),
    ]

    /// Per-instrument rival pairs, matching the web's `DEMO_INSTRUMENT_RIVALS`.
    static let instrumentRivals: [Instrument: (above: RivalEntry, below: RivalEntry)] = [
        .lead: (
            .init(name: "StageKnight", shared: 140, ahead: 78, behind: 62),
            .init(name: "FretBlaze", shared: 125, ahead: 48, behind: 77)
        ),
        .drums: (
            .init(name: "BeatLegend", shared: 132, ahead: 80, behind: 52),
            .init(name: "RhythmEdge", shared: 115, ahead: 40, behind: 75)
        ),
        .vocals: (
            .init(name: "VocalStorm", shared: 128, ahead: 74, behind: 54),
            .init(name: "TopClutch", shared: 110, ahead: 42, behind: 68)
        ),
    ]

    // MARK: Score history (Song Info charts)

    /// One tracked score point, matching the web's Song Info chart demo data.
    struct ScorePoint: Identifiable {
        let id = UUID()
        let label: String
        let score: Int
        let accuracy: Double
        let isFullCombo: Bool
    }

    static let scoreHistory: [ScorePoint] = [
        .init(label: "9/12", score: 218_400, accuracy: 62, isFullCombo: false),
        .init(label: "9/13", score: 347_100, accuracy: 78, isFullCombo: false),
        .init(label: "Today", score: 486_500, accuracy: 100, isFullCombo: true),
    ]

    /// Top-scores leaderboard for one song/instrument, matching the web's `TopScoresDemo`.
    struct TopScoreEntry: Identifiable {
        let rank: Int
        let name: String
        let score: Int
        let accuracyPercent: Int
        let isFullCombo: Bool
        var id: Int { rank }
    }

    static let topScores: [TopScoreEntry] = [
        .init(rank: 1, name: "AceSolo", score: 486_500, accuracyPercent: 100, isFullCombo: true),
        .init(rank: 2, name: "RiffMaster", score: 412_300, accuracyPercent: 98, isFullCombo: false),
        .init(rank: 3, name: "ChordKing", score: 347_100, accuracyPercent: 97, isFullCombo: false),
        .init(rank: 4, name: "PickSlayer", score: 289_600, accuracyPercent: 96, isFullCombo: false),
    ]

    /// A player's own score history, matching the web's `ViewAllDemo`/`ScoreListDemo`.
    static let ownScores: [TopScoreEntry] = [
        .init(rank: 1, name: "9/12/26", score: 486_500, accuracyPercent: 100, isFullCombo: true),
        .init(rank: 2, name: "9/05/26", score: 412_300, accuracyPercent: 99, isFullCombo: false),
        .init(rank: 3, name: "8/22/26", score: 347_100, accuracyPercent: 97, isFullCombo: false),
        .init(rank: 4, name: "8/08/26", score: 289_600, accuracyPercent: 95, isFullCombo: false),
    ]

    // MARK: Percentiles

    /// One percentile bucket row, matching the web's `PercentileDemo`.
    struct PercentileBucket: Identifiable {
        let percent: Int
        let count: Int
        var id: Int { percent }
    }

    static let percentileBuckets: [PercentileBucket] = [
        .init(percent: 1, count: 3), .init(percent: 5, count: 12), .init(percent: 10, count: 28),
        .init(percent: 25, count: 55), .init(percent: 50, count: 89), .init(percent: 100, count: 142),
    ]

    // MARK: Rival song comparisons (Rivals detail)

    /// One head-to-head rank pair, matching the web's `RivalsDetailDemo` "Closest Battles"
    /// rank data. Song titles come from the live catalogue, never this pool.
    struct RivalComparison: Identifiable {
        let userRank: Int
        let rivalRank: Int
        let userScore: Int
        let rivalScore: Int
        var id: Int { userRank }
    }

    static let closestBattles: [RivalComparison] = [
        .init(userRank: 14, rivalRank: 15, userScore: 988_000, rivalScore: 987_500),
        .init(userRank: 23, rivalRank: 22, userScore: 965_000, rivalScore: 965_800),
        .init(userRank: 8, rivalRank: 9, userScore: 995_200, rivalScore: 994_900),
    ]
}
