import Foundation

// MARK: - Errors

/// Rivals-specific validation failures. HTTP and network failures use the
/// shared `FestivalAPIError` vocabulary from the unified request helper
/// (`FestivalAPI+Request.swift`); convert either with `ServiceIssue(_:)`.
public enum RivalsAPIError: LocalizedError, Equatable, Sendable {
    case invalidResource
    case invalidResponse

    /// Explain a Rivals failure without exposing raw server text.
    public var errorDescription: String? {
        switch self {
        case .invalidResource:
            "That rival comparison is unavailable."
        case .invalidResponse:
            "The service returned data we could not read. Try again."
        }
    }
}

// MARK: - Ranking metric

/// Ranking metrics accepted by `rankBy` on the leaderboard-rivals endpoints.
///
/// Mirrors the web's `RankingMetric` union (`packages/core/src/api/serverTypes.ts`);
/// kept as its own small enum rather than depending on the Leaderboards lane's
/// (not yet landed) shared type.
public enum RivalRankMetric: String, CaseIterable, Sendable, Identifiable, Equatable, Hashable {
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

    /// Whether this metric is experimental (pattern `experimental-ranks`).
    public var isExperimental: Bool { self != .totalscore }

    /// The metrics the Leaderboard Rivals Rank By offers (see ``ExperimentalRanks``).
    ///
    /// - Parameter experimentalRanks: The Settings switch.
    /// - Returns: Total Score alone while off; every metric while on.
    public static func enabled(experimentalRanks: Bool) -> [RivalRankMetric] {
        experimentalRanks ? allCases : [.totalscore]
    }

    /// This metric, or Total Score when it is experimental and the switch is off (web
    /// `RivalsPage` / `AllRivalsPage` `coerceRankingMetric`).
    ///
    /// - Parameter experimentalRanks: The Settings switch.
    /// - Returns: The metric in effect.
    public func coerced(experimentalRanks: Bool) -> RivalRankMetric {
        experimentalRanks || !isExperimental ? self : .totalscore
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

// MARK: - Rival scope (typed `AppRoute` payload)

/// Which flow/scope produced a rival row or list, carried directly as a typed,
/// `Hashable` payload on `AppRoute.allRivals`/`.rivalDetail`/`.rivalry`.
///
/// The web learns this from React Router's `location.state`, a side channel
/// `AppRoute`'s plain value-typed cases don't have. Earlier native passes filled
/// that gap with a process-lifetime `RivalNavigationBridge` singleton keyed by
/// rival account ID — but a singleton stash breaks deep links (a route restored
/// from state restoration, a universal link, or `DebugLaunchRoute` never stashed
/// anything) and can desync across independent navigation stacks. `RivalScope`
/// replaces it: the scope now travels as part of the route itself, so any way of
/// reaching a rival route (tap, deep link, restored state) carries the same
/// information the destination screen needs.
public enum RivalScope: Hashable, Sendable {
    /// One or more solo-chart instruments whose "shared songs" rivals lists are
    /// merged client-side (`FestivalSession.combinedRivalDetail`). A single
    /// instrument is the common case (one `RivalsScreen`/`CompeteScreen` row);
    /// two or more is "Common Rivals" — every instrument's rivals list intersected
    /// (`RivalCommonRivals.intersect`).
    case song(instruments: [String])
    /// A global per-instrument leaderboard's neighboring rivals.
    case leaderboard(instrument: String, rankBy: RivalRankMetric)
    /// A server-computed cross-instrument "combo" or Pro Drums family scope
    /// (`RivalCombo.deriveScope`), queried as a single distinct rival list rather
    /// than merged client-side. `instruments` are the scope's constituent charts,
    /// kept alongside `token` for display and for the fallback merge path.
    case combo(token: String, instruments: [String])
}

extension RivalScope {
    private static let songPrefix = "song:"
    private static let leaderboardPrefix = "leaderboard:"
    private static let comboPrefix = "combo:"

    /// This scope with a leaderboard scope's metric narrowed by the Settings switch
    /// (web `AllRivalsPage` / `RivalryPage` / `RivalDetailPage` `coerceRankingMetric`):
    /// a saved or deep-linked experimental metric reads Total Score while it is off.
    ///
    /// - Parameter experimentalRanks: The Settings switch.
    /// - Returns: The scope in effect.
    public func coerced(experimentalRanks: Bool) -> RivalScope {
        guard case let .leaderboard(instrument, rankBy) = self else { return self }
        return .leaderboard(instrument: instrument, rankBy: rankBy.coerced(experimentalRanks: experimentalRanks))
    }

    /// Compact colon-separated token used only by `DebugLaunchRoute`
    /// (`FST_DEBUG_ROUTE`) to open a rival route with a specific scope; `AppRoute`
    /// itself carries `RivalScope` directly and never encodes it as a string.
    public var debugToken: String {
        switch self {
        case let .song(instruments):
            Self.songPrefix + instruments.joined(separator: ",")
        case let .leaderboard(instrument, rankBy):
            Self.leaderboardPrefix + instrument + ":" + rankBy.rawValue
        case let .combo(token, instruments):
            Self.comboPrefix + token + ":" + instruments.joined(separator: ",")
        }
    }

    /// Parse a token produced by `debugToken`.
    ///
    /// - Parameter debugToken: Raw scope segment of a debug launch route.
    /// - Returns: The scope it encodes, or `nil` for a malformed token.
    public init?(debugToken: String) {
        if debugToken.hasPrefix(Self.leaderboardPrefix) {
            let rest = debugToken.dropFirst(Self.leaderboardPrefix.count)
            let parts = rest.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let rankBy = RivalRankMetric(rawValue: String(parts[1])) else {
                return nil
            }
            self = .leaderboard(instrument: String(parts[0]), rankBy: rankBy)
            return
        }
        if debugToken.hasPrefix(Self.comboPrefix) {
            let rest = debugToken.dropFirst(Self.comboPrefix.count)
            let parts = rest.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            self = .combo(token: String(parts[0]), instruments: parts[1].split(separator: ",").map(String.init))
            return
        }
        if debugToken.hasPrefix(Self.songPrefix) {
            let rest = debugToken.dropFirst(Self.songPrefix.count)
            self = .song(instruments: rest.split(separator: ",").map(String.init))
            return
        }
        return nil
    }
}

// MARK: - Cross-instrument combo scope (native port of `comboUtils.ts`/`combos.ts`)

/// A cross-instrument scope the Rivals hub derives from Settings' visible
/// instruments, mirroring the web's `deriveRivalScopeFromSettings`.
public enum RivalComboScope: Sendable, Equatable {
    /// A within-group hex-bitmask combo (e.g. Lead+Bass, or all four OG-band charts).
    case instruments(comboId: String, instruments: [Instrument])
    /// The Pro Drums family special case (Pro Cymbals + Pro Drums), which is not a
    /// bitmask combo on the server (`PRO_DRUMS_RIVAL_SCOPE`).
    case proDrumsFamily

    /// Path segment sent to the server in place of a single instrument.
    public var token: String {
        switch self {
        case let .instruments(comboId, _): comboId
        case .proDrumsFamily: RivalCombo.proDrumsToken
        }
    }

    /// The scope's constituent instruments, in canonical order.
    public var instruments: [Instrument] {
        switch self {
        case let .instruments(_, instruments): instruments
        case .proDrumsFamily: [.proCymbals, .proDrums]
        }
    }

    /// User-facing label, mirroring the web's `comboDisplayLabel`.
    public var label: String {
        switch self {
        case .proDrumsFamily: "Pro Drums Family"
        case .instruments: "Combo"
        }
    }
}

/// Native port of `comboUtils.ts`/`combos.ts`'s bitmask combo-ID system.
public enum RivalCombo {
    /// The Pro Drums family's non-bitmask scope token (`PRO_DRUMS_RIVAL_SCOPE`).
    public static let proDrumsToken = "pro_drums"

    /// Instrument groups a combo may be drawn from; only within-group combos are
    /// supported (native `INSTRUMENT_GROUPS`: `0x0f` OG band, `0x30` Pro Strings).
    private static let groups: [Set<Instrument>] = [
        [.lead, .bass, .drums, .vocals],
        [.proLead, .proBass],
    ]
    private static let proDrumsFamily: Set<Instrument> = [.proCymbals, .proDrums]

    /// Bit position of an instrument in the canonical combo mask. `Instrument`'s
    /// case order matches the web's `SERVER_INSTRUMENT_KEYS`/`COMBO_INSTRUMENTS`.
    private static func bit(for instrument: Instrument) -> Int {
        Instrument.allCases.firstIndex(of: instrument) ?? 0
    }

    /// Compute the hex bitmask combo ID for a set of instruments (native
    /// `comboIdFromInstruments`), zero-padded to at least 2 digits.
    ///
    /// - Parameter instruments: Instruments to encode.
    /// - Returns: Lowercase hex combo ID.
    public static func comboId(for instruments: [Instrument]) -> String {
        var mask = 0
        for instrument in instruments { mask |= 1 << bit(for: instrument) }
        let hex = String(mask, radix: 16)
        return hex.count < 2 ? String(repeating: "0", count: 2 - hex.count) + hex : hex
    }

    /// Whether every instrument in the set belongs to a single supported group
    /// (native `isWithinGroupCombo`); a combo needs 2+ instruments.
    private static func isWithinGroup(_ instruments: [Instrument]) -> Bool {
        guard instruments.count >= 2 else { return false }
        let set = Set(instruments)
        return groups.contains { $0.isSuperset(of: set) }
    }

    /// Derive the single cross-instrument rival scope the Rivals hub shows,
    /// mirroring `deriveRivalScopeFromSettings`: the Pro Drums family special case
    /// first, then a within-group bitmask combo, else `nil`.
    ///
    /// - Parameter instruments: Settings-visible instruments, in any order.
    /// - Returns: The derived scope, or `nil` when the visible set doesn't qualify
    ///   (fewer than two instruments, or a cross-group mix).
    public static func deriveScope(visible instruments: [Instrument]) -> RivalComboScope? {
        let set = Set(instruments)
        if set == proDrumsFamily { return .proDrumsFamily }
        guard isWithinGroup(instruments) else { return nil }
        return .instruments(comboId: comboId(for: instruments), instruments: instruments)
    }
}

// MARK: - Common Rivals (native port of `RivalsPage.tsx`'s `commonRivals` memo)

/// Rivals present in every one of several loaded per-instrument rivals lists.
public enum RivalCommonRivals {
    /// Intersect two or more instruments' rivals lists, mirroring the web's
    /// `commonRivals` `useMemo` in `RivalsPage.tsx`: a rival must appear
    /// (above or below) in *every* supplied list to qualify. Direction is decided
    /// by majority vote across the lists the rival appeared in, ties favoring
    /// "above"; the highest-`sharedSongCount` entry represents the rival.
    ///
    /// - Parameter perInstrument: Each loaded instrument's rivals list. Fewer than
    ///   two lists trivially produce no common rivals.
    /// - Returns: Above/below groups, each sorted by `rivalScore` descending.
    public static func intersect(
        _ perInstrument: [RivalsListResponse]
    ) -> (above: [RivalSummary], below: [RivalSummary]) {
        guard perInstrument.count >= 2 else { return ([], []) }

        var counts: [String: Int] = [:]
        var aboveByAccount: [String: [RivalSummary]] = [:]
        var belowByAccount: [String: [RivalSummary]] = [:]
        for list in perInstrument {
            var seen = Set<String>()
            let isAbove = Set(list.above.map(\.accountId))
            for rival in list.above + list.below where seen.insert(rival.accountId).inserted {
                counts[rival.accountId, default: 0] += 1
                if isAbove.contains(rival.accountId) {
                    aboveByAccount[rival.accountId, default: []].append(rival)
                } else {
                    belowByAccount[rival.accountId, default: []].append(rival)
                }
            }
        }

        let threshold = perInstrument.count
        var above: [RivalSummary] = []
        var below: [RivalSummary] = []
        for (accountId, count) in counts where count >= threshold {
            let aboveEntries = aboveByAccount[accountId] ?? []
            let belowEntries = belowByAccount[accountId] ?? []
            let allEntries = aboveEntries + belowEntries
            guard let first = allEntries.first else { continue }
            let best = allEntries.dropFirst().reduce(first) { current, next in
                current.sharedSongCount >= next.sharedSongCount ? current : next
            }
            if aboveEntries.count >= belowEntries.count {
                above.append(best)
            } else {
                below.append(best)
            }
        }
        above.sort { $0.rivalScore > $1.rivalScore }
        below.sort { $0.rivalScore > $1.rivalScore }
        return (above, below)
    }
}
