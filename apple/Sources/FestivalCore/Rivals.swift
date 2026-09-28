import Foundation

// MARK: - Errors

/// Read-only failures for the Rivals and Compete domain, kept separate from
/// `FestivalAPIError` because Rivals reads bypass the publication-pinned
/// `FestivalAPI.read(_:)` pipeline (see `FestivalAPI+Rivals.swift`).
public enum RivalsAPIError: LocalizedError, Equatable, Sendable {
    case invalidResource
    case invalidResponse
    case httpStatus(Int)
    case unavailable(retryAfter: String?)

    /// Explain a Rivals failure without exposing raw server text.
    public var errorDescription: String? {
        switch self {
        case .invalidResource:
            "That rival comparison is unavailable."
        case .invalidResponse:
            "The service returned data we could not read. Try again."
        case let .httpStatus(status) where status == 429:
            "Too many requests. Try again shortly."
        case .httpStatus:
            "The service returned an unexpected error. Try again."
        case .unavailable:
            "Rivals data is temporarily unavailable. Try again shortly."
        }
    }
}

// MARK: - Ranking metric

/// Ranking metrics accepted by `rankBy` on the leaderboard-rivals endpoints.
///
/// Mirrors the web's `RankingMetric` union (`packages/core/src/api/serverTypes.ts`);
/// kept as its own small enum rather than depending on the Leaderboards lane's
/// (not yet landed) shared type.
public enum RivalRankMetric: String, CaseIterable, Sendable, Identifiable, Equatable {
    case totalscore
    case adjusted
    case weighted
    case fcrate
    case maxscore

    public var id: String { rawValue }

    /// User-facing label for a metric picker.
    public var label: String {
        switch self {
        case .totalscore: "Total Score"
        case .adjusted: "Adjusted"
        case .weighted: "Weighted"
        case .fcrate: "FC Rate"
        case .maxscore: "Max Score"
        }
    }
}

// MARK: - Combo overview (`GET /api/player/:accountId/rivals`)

/// One instrument/combo scope's rival counts from the overview endpoint.
public struct RivalComboSummary: Decodable, Sendable, Equatable, Identifiable {
    public let combo: String
    public let aboveCount: Int
    public let belowCount: Int

    public var id: String { combo }
}

/// Response from `GET /api/player/{accountId}/rivals`.
public struct RivalsOverviewResponse: Decodable, Sendable, Equatable {
    public let accountId: String
    public let computedAt: String?
    public let combos: [RivalComboSummary]
}

// MARK: - Rival summary (`GET /api/player/:accountId/rivals/:combo`)

/// One rival's aggregate standing against the selected player for a combo/instrument.
///
/// `rivalScore` and `avgSignedDelta` are server-computed floating point values
/// (verified against a live capture), not integer counts.
public struct RivalSummary: Decodable, Sendable, Equatable, Identifiable {
    public let accountId: String
    public let displayName: String?
    public let rivalScore: Double
    public let sharedSongCount: Int
    public let aheadCount: Int
    public let behindCount: Int
    public let avgSignedDelta: Double

    public var id: String { accountId }
}

/// Response from `GET /api/player/{accountId}/rivals/{combo}`.
public struct RivalsListResponse: Decodable, Sendable, Equatable {
    public let combo: String
    public let above: [RivalSummary]
    public let below: [RivalSummary]

    /// An empty list, used to normalize the endpoint's HTTP 404 "no rivals" response.
    ///
    /// - Parameter combo: Requested combo/instrument scope.
    /// - Returns: A valid, empty result rather than a thrown error.
    public static func empty(combo: String) -> RivalsListResponse {
        RivalsListResponse(combo: combo, above: [], below: [])
    }

    public var isEmpty: Bool { above.isEmpty && below.isEmpty }
}

// MARK: - Leaderboard rival summary (`GET /api/player/:accountId/leaderboard-rivals/:instrument`)

/// A rival drawn from the global instrument leaderboard rather than shared songs.
public struct LeaderboardRivalSummary: Decodable, Sendable, Equatable, Identifiable {
    public let accountId: String
    public let displayName: String?
    public let sharedSongCount: Int
    public let aheadCount: Int
    public let behindCount: Int
    public let avgSignedDelta: Double
    public let leaderboardRank: Int
    public let userLeaderboardRank: Int

    public var id: String { accountId }
}

/// Response from `GET /api/player/{accountId}/leaderboard-rivals/{instrument}`.
public struct LeaderboardRivalsListResponse: Decodable, Sendable, Equatable {
    public let instrument: String
    public let rankBy: String
    public let userRank: Int?
    public let above: [LeaderboardRivalSummary]
    public let below: [LeaderboardRivalSummary]

    public var isEmpty: Bool { above.isEmpty && below.isEmpty }
}

/// Common display shape shared by `RivalSummary` and `LeaderboardRivalSummary`,
/// mirroring the web's `RivalLike` type in `RivalRow.tsx`.
public protocol RivalRowDisplayable: Identifiable, Sendable {
    var accountId: String { get }
    var displayName: String? { get }
    var sharedSongCount: Int { get }
    var aheadCount: Int { get }
    var behindCount: Int { get }
}

extension RivalSummary: RivalRowDisplayable {}
extension LeaderboardRivalSummary: RivalRowDisplayable {}

/// Which half of a rivals list a row came from: ahead of the player, or behind.
public enum RivalDirection: String, Sendable {
    case above
    case below
}

// MARK: - Rival detail / rivalry (`GET /api/player/:accountId/rivals/:combo/:rivalId`
// and `GET /api/player/:accountId/leaderboard-rivals/:instrument/:rivalId`)

/// Minimal rival identity echoed back by the detail endpoints.
public struct RivalIdentity: Decodable, Sendable, Equatable {
    public let accountId: String
    public let displayName: String?

    /// Create an identity (the synthesized memberwise initializer is internal-only
    /// once every property is `public`; this explicit one lets other modules,
    /// such as `FestivalSession+Rivals.swift`, construct merged results).
    public init(accountId: String, displayName: String?) {
        self.accountId = accountId
        self.displayName = displayName
    }
}

/// One shared song's rank/score comparison against a specific rival.
public struct RivalSongComparison: Decodable, Sendable, Equatable, Identifiable {
    public let songId: String
    public let title: String?
    public let artist: String?
    public let instrument: String
    public let userInstrument: String?
    public let rivalInstrument: String?
    public let userRank: Int
    public let rivalRank: Int
    /// Positive: the player leads (better/lower rank number). Negative: the rival leads.
    public let rankDelta: Int
    public let userScore: Int?
    public let rivalScore: Int?

    public var id: String {
        "\(songId)|\(instrument)|\(userInstrument ?? "")|\(rivalInstrument ?? "")"
    }
}

/// A song either player has scored that the other has not (`songsToCompete` /
/// `yourExclusiveSongs` on the detail response); only populated when the service
/// computed live gaps (`includeGaps`), which this app does not currently request.
public struct RivalGapSong: Decodable, Sendable, Equatable, Identifiable {
    public let songId: String
    public let title: String?
    public let artist: String?
    public let instrument: String
    public let score: Int
    public let rank: Int

    public var id: String { "\(songId)|\(instrument)" }
}

/// Response shape shared by the song-combo and leaderboard rival detail endpoints.
///
/// The two live routes return slightly different envelopes (`combo`/`offset`/`limit`
/// vs. `instrument`/`rankBy`); both are optional here so one type can decode either.
public struct RivalDetailResponse: Decodable, Sendable, Equatable {
    public let rival: RivalIdentity
    public let combo: String?
    public let instrument: String?
    public let rankBy: String?
    public let source: String?
    public let totalSongs: Int
    public let offset: Int?
    public let limit: Int?
    public let sort: String
    public let songs: [RivalSongComparison]
    public let songsToCompete: [RivalGapSong]?
    public let yourExclusiveSongs: [RivalGapSong]?

    /// Create a detail result (the synthesized memberwise initializer is
    /// internal-only once every property is `public`; this explicit one lets
    /// other modules, such as `FestivalSession+Rivals.swift`, build a merged
    /// result from several single-instrument reads).
    public init(
        rival: RivalIdentity, combo: String?, instrument: String?, rankBy: String?,
        source: String?, totalSongs: Int, offset: Int?, limit: Int?, sort: String,
        songs: [RivalSongComparison], songsToCompete: [RivalGapSong]?,
        yourExclusiveSongs: [RivalGapSong]?
    ) {
        self.rival = rival
        self.combo = combo
        self.instrument = instrument
        self.rankBy = rankBy
        self.source = source
        self.totalSongs = totalSongs
        self.offset = offset
        self.limit = limit
        self.sort = sort
        self.songs = songs
        self.songsToCompete = songsToCompete
        self.yourExclusiveSongs = yourExclusiveSongs
    }

    /// An empty detail result, used to normalize the endpoint's HTTP 404
    /// "no precomputed song data" response into a plain empty state.
    ///
    /// - Parameters:
    ///   - rivalId: Requested rival account ID.
    ///   - displayName: Rival name already known from the originating list row.
    /// - Returns: A valid, empty detail payload.
    public static func empty(rivalId: String, displayName: String?) -> RivalDetailResponse {
        RivalDetailResponse(
            rival: RivalIdentity(accountId: rivalId, displayName: displayName),
            combo: nil, instrument: nil, rankBy: nil, source: nil,
            totalSongs: 0, offset: nil, limit: nil, sort: "closest",
            songs: [], songsToCompete: [], yourExclusiveSongs: []
        )
    }
}

// MARK: - Rivalry categorization (native port of `rivalCategories.ts`)

/// One themed grouping of a rival detail's shared songs, for the detail hub and
/// as the "mode" a `Rivalry` page drills into.
public struct RivalCategory: Identifiable, Sendable, Equatable {
    public let key: String
    public let title: String
    public let subtitle: String
    public let songs: [RivalSongComparison]

    public var id: String { key }
}

/// Splits a rival's shared songs into the same themed buckets as the web's
/// `categorizeRivalSongs` (`FortniteFestivalWeb/src/pages/rivals/helpers/rivalCategories.ts`),
/// keyed identically so `AppRoute.rivalry(mode:)` round-trips.
public enum RivalCategorization {
    private static let closestBattlesCount = 5

    /// Categorize a rival's compared songs into direction/magnitude buckets.
    ///
    /// - Parameter songs: All songs shared with one rival for the active scope.
    /// - Returns: Non-empty categories in the same order as the web page.
    public static func categorize(_ songs: [RivalSongComparison]) -> [RivalCategory] {
        guard !songs.isEmpty else { return [] }

        let userLeads = songs.filter { $0.rankDelta > 0 }.sorted { $0.rankDelta < $1.rankDelta }
        let rivalLeads = songs.filter { $0.rankDelta < 0 }.sorted { $0.rankDelta > $1.rankDelta }
        let closestBattles = songs
            .sorted { abs($0.rankDelta) < abs($1.rankDelta) }
            .prefix(closestBattlesCount)

        var categories: [RivalCategory] = []

        if !closestBattles.isEmpty {
            categories.append(RivalCategory(
                key: "closest_battles", title: "Closest Battles",
                subtitle: "Your tightest races with this rival.",
                songs: Array(closestBattles)
            ))
        }

        if !rivalLeads.isEmpty {
            let third = Int((Double(rivalLeads.count) / 2).rounded(.up))
            let almostPassed = Array(rivalLeads.prefix(third))
            let slippingAway = Array(rivalLeads.dropFirst(third))
            if !almostPassed.isEmpty {
                categories.append(RivalCategory(
                    key: "almost_passed", title: "Almost Passed",
                    subtitle: "Rankings where you're closing in fast.",
                    songs: almostPassed
                ))
            }
            if !slippingAway.isEmpty {
                categories.append(RivalCategory(
                    key: "slipping_away", title: "Slipping Away",
                    subtitle: "Rankings where the gap keeps growing.",
                    songs: slippingAway
                ))
            }
        }

        if !userLeads.isEmpty {
            let third = Int((Double(userLeads.count) / 3).rounded(.up))
            let barelyWinning = Array(userLeads.prefix(third))
            let pullingForward = Array(userLeads.dropFirst(third).prefix(third))
            let dominatingThem = Array(userLeads.dropFirst(third * 2))
            if !barelyWinning.isEmpty {
                categories.append(RivalCategory(
                    key: "barely_winning", title: "Barely Winning",
                    subtitle: "Your closest leads over this rival.",
                    songs: barelyWinning
                ))
            }
            if !pullingForward.isEmpty {
                categories.append(RivalCategory(
                    key: "pulling_forward", title: "Pulling Forward",
                    subtitle: "Leads you're extending.",
                    songs: pullingForward
                ))
            }
            if !dominatingThem.isEmpty {
                categories.append(RivalCategory(
                    key: "dominating_them", title: "Dominating Them",
                    subtitle: "Commanding leads over this rival.",
                    songs: dominatingThem
                ))
            }
        }

        return categories
    }
}

// MARK: - Cross-push navigation context

/// Which flow produced a rival row — the song/combo rivals list, or a global
/// instrument leaderboard — mirroring the web's `RivalRouteState.source`.
public enum RivalRouteSource: String, Sendable, Equatable {
    case song
    case leaderboard
}

/// Context a Rivals hub or Compete row stashes immediately before pushing
/// `AppRoute.rivalDetail`/`.rivalry`, so the detail screen knows which combo or
/// leaderboard instrument produced the tapped row.
///
/// The web carries this through React Router's `location.state`; native
/// `AppRoute` cases are plain `Hashable` values with no side channel, so
/// `RivalNavigationBridge` fills the gap for exactly one push at a time.
public struct RivalRouteContext: Sendable, Equatable {
    public let source: RivalRouteSource
    /// Instrument raw values to merge results from (song source), or a single
    /// leaderboard instrument (leaderboard source).
    public let instruments: [String]
    public let rankBy: RivalRankMetric

    /// Create a song-scope context for one or more instrument keys.
    public static func song(instruments: [String]) -> RivalRouteContext {
        RivalRouteContext(source: .song, instruments: instruments, rankBy: .totalscore)
    }

    /// Create a leaderboard-scope context for one instrument.
    public static func leaderboard(
        instrument: String, rankBy: RivalRankMetric
    ) -> RivalRouteContext {
        RivalRouteContext(source: .leaderboard, instruments: [instrument], rankBy: rankBy)
    }
}

/// Process-lifetime, `MainActor`-confined bridge for `RivalRouteContext`.
///
/// Keyed by rival account ID and consumed once; a screen reached without a
/// stashed context (deep link, cold navigation) falls back to its own default
/// rather than failing, per the app's "everything player-only degrades
/// gracefully" rule.
@MainActor
public final class RivalNavigationBridge {
    public static let shared = RivalNavigationBridge()

    private var pending: [String: RivalRouteContext] = [:]

    private init() {}

    /// Record scope context immediately before pushing a rival route.
    ///
    /// - Parameters:
    ///   - context: Scope that produced the tapped row.
    ///   - rivalId: Target rival account ID.
    public func stash(_ context: RivalRouteContext, forRivalId rivalId: String) {
        pending[rivalId] = context
    }

    /// Consume (remove) any stashed context for a rival, once.
    ///
    /// - Parameter rivalId: Rival account ID the destination screen is showing.
    /// - Returns: The stashed context, if one was set for this exact push.
    public func consume(forRivalId rivalId: String) -> RivalRouteContext? {
        pending.removeValue(forKey: rivalId)
    }
}

// MARK: - `AllRivals` category encoding

/// Encodes/decodes the `category` string carried by `AppRoute.allRivals(category:)`.
///
/// The web's all-rivals route takes independent `category`/`mode`/`rankBy` query
/// parameters; native `AppRoute.allRivals` has a single `category: String` (an
/// orchestrator-owned seam this lane cannot extend), so the scope and source are
/// packed into one colon-separated token here instead.
public enum RivalAllCategory: Sendable, Equatable {
    case song(instrument: String)
    case leaderboard(instrument: String, rankBy: RivalRankMetric)

    private static let songPrefix = "song:"
    private static let leaderboardPrefix = "leaderboard:"

    /// Pack a scope into the single string `AppRoute.allRivals(category:)` carries.
    public var encoded: String {
        switch self {
        case let .song(instrument):
            return Self.songPrefix + instrument
        case let .leaderboard(instrument, rankBy):
            return Self.leaderboardPrefix + instrument + ":" + rankBy.rawValue
        }
    }

    /// Decode a category string produced by `encoded`.
    ///
    /// - Parameter category: Raw `AppRoute.allRivals` category payload.
    /// - Returns: The scope it encodes, or `nil` for an unrecognized token
    ///   (e.g. a future deep link); callers show an empty/error state rather
    ///   than guessing.
    public static func decode(_ category: String) -> RivalAllCategory? {
        if category.hasPrefix(leaderboardPrefix) {
            let rest = category.dropFirst(leaderboardPrefix.count)
            let parts = rest.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let rankBy = RivalRankMetric(rawValue: String(parts[1])) else {
                return nil
            }
            return .leaderboard(instrument: String(parts[0]), rankBy: rankBy)
        }
        if category.hasPrefix(songPrefix) {
            return .song(instrument: String(category.dropFirst(songPrefix.count)))
        }
        // Back-compat: a bare instrument raw value with no prefix is a song scope.
        return .song(instrument: category)
    }
}
