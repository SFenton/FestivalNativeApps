import Foundation
import FestivalCore

/// Rivals/Compete reads for the selected player.
///
/// Unlike Songs/Shop/Player reads, these do not go through `session.observe(publicationId:)` —
/// Rivals data is not part of the catalogue/score publication contract (see
/// `FestivalAPI+Rivals.swift`), so there is no generation to invalidate against.
extension FestivalSession {
    /// The currently selected player's account ID, if any.
    ///
    /// - Throws: `FestivalAPIError.invalidSelectedProfile` when no player is selected,
    ///   so call sites can surface the same "choose a profile" messaging as other
    ///   player-only reads instead of a generic nil-unwrap crash.
    private func requireSelectedAccountId() throws -> String {
        guard let selectedPlayer else {
            throw FestivalAPIError.invalidSelectedProfile
        }
        return selectedPlayer.accountId
    }

    /// Rivals sharing songs with the selected player on one instrument.
    ///
    /// - Parameter instrument: Solo chart scope.
    /// - Returns: Rivals ahead of and behind the player.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func rivalsList(instrument: Instrument) async throws -> RivalsListResponse {
        try await client().rivalsList(accountId: requireSelectedAccountId(), instrument: instrument)
    }

    /// A cross-instrument "combo" or Pro Drums family scope's rivals for the
    /// selected player (`RivalCombo.deriveScope`).
    ///
    /// - Parameter token: `RivalComboScope.token`.
    /// - Returns: Rivals ahead of and behind the player under this scope.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func rivalsComboList(token: String) async throws -> RivalsListResponse {
        try await client().rivalsComboList(accountId: requireSelectedAccountId(), token: token)
    }

    /// A combo/Pro-Drums-family rival's shared-song comparison.
    ///
    /// - Parameters:
    ///   - token: `RivalComboScope.token`.
    ///   - rivalId: Target rival's account ID.
    ///   - sort: `closest`, `they_lead` or `you_lead`.
    /// - Returns: Compared songs for this scope.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func rivalComboDetail(
        token: String, rivalId: String, sort: String = "closest"
    ) async throws -> RivalDetailResponse {
        try await client().rivalComboDetail(
            accountId: requireSelectedAccountId(), token: token, rivalId: rivalId, sort: sort
        )
    }

    /// One rival's shared-song comparison on one instrument.
    ///
    /// - Parameters:
    ///   - instrument: Solo chart scope.
    ///   - rivalId: Target rival's account ID.
    ///   - sort: `closest`, `they_lead` or `you_lead`.
    /// - Returns: Compared songs for this instrument.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func rivalDetail(
        instrument: Instrument, rivalId: String, sort: String = "closest"
    ) async throws -> RivalDetailResponse {
        try await client().rivalDetail(
            accountId: requireSelectedAccountId(), instrument: instrument, rivalId: rivalId, sort: sort
        )
    }

    /// A rival's shared-song comparison merged across several instruments (a
    /// simplified native stand-in for the web's `fetchCombinedRivalDetail`,
    /// which additionally supports hex-bitmask "combo" scopes this app does
    /// not query).
    ///
    /// - Parameters:
    ///   - instruments: One or more solo chart scopes to merge, deduplicated.
    ///   - rivalId: Target rival's account ID.
    ///   - sort: `closest`, `they_lead` or `you_lead`.
    /// - Returns: The union of compared songs across all requested instruments.
    /// - Throws: No selected player; a per-instrument failure is only thrown when
    ///   every requested instrument failed.
    func combinedRivalDetail(
        instruments: [Instrument], rivalId: String, sort: String = "closest"
    ) async throws -> RivalDetailResponse {
        let unique = Array(Set(instruments))
        guard let first = unique.first else {
            throw FestivalAPIError.invalidResource
        }
        if unique.count == 1 {
            return try await rivalDetail(instrument: first, rivalId: rivalId, sort: sort)
        }
        // Sequential rather than concurrent: at most a handful of instruments per
        // rival push, and this keeps every call on the session's own MainActor
        // isolation without crossing into a detached task group.
        var succeeded: [RivalDetailResponse] = []
        var firstError: Error?
        for instrument in unique {
            do {
                succeeded.append(try await rivalDetail(instrument: instrument, rivalId: rivalId, sort: sort))
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        guard let base = succeeded.first else {
            throw firstError ?? FestivalAPIError.invalidResponse
        }
        var seen = Set<String>()
        var songs: [RivalSongComparison] = []
        for detail in succeeded {
            for song in detail.songs where seen.insert(song.id).inserted {
                songs.append(song)
            }
        }
        let displayName = succeeded.compactMap(\.rival.displayName).first ?? base.rival.displayName
        return RivalDetailResponse(
            rival: RivalIdentity(accountId: base.rival.accountId, displayName: displayName),
            combo: unique.map(\.rawValue).joined(separator: ","),
            instrument: nil, rankBy: nil, source: base.source,
            totalSongs: songs.count, offset: 0, limit: 0, sort: base.sort,
            songs: songs, songsToCompete: nil, yourExclusiveSongs: nil
        )
    }

    /// Resolve a rival detail read for a typed `RivalScope`, falling back to
    /// merging every Settings-visible instrument when no scope is known (a rival
    /// route reached without one: deep link, restored state, cold `DebugLaunchRoute`).
    ///
    /// Shared by `RivalDetailScreen` and `RivalryScreen` so both resolve a pushed
    /// `AppRoute.rivalDetail`/`.rivalry`'s optional scope identically.
    ///
    /// - Parameters:
    ///   - scope: The route's carried scope, or `nil`.
    ///   - rivalId: Target rival's account ID.
    ///   - visibleInstruments: Settings-visible instruments, used only as the
    ///     fallback merge set when `scope` is `nil` or names no valid instrument.
    /// - Returns: Compared songs for the resolved scope.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func rivalDetail(
        forScope scope: RivalScope?, rivalId: String, visibleInstruments: [Instrument]
    ) async throws -> RivalDetailResponse {
        switch scope {
        case let .leaderboard(instrumentRaw, rankBy):
            guard let instrument = Instrument(rawValue: instrumentRaw) else {
                return try await fallbackRivalDetail(rivalId: rivalId, visibleInstruments: visibleInstruments)
            }
            return try await leaderboardRivalDetail(instrument: instrument, rivalId: rivalId, rankBy: rankBy)
        case let .song(instrumentsRaw):
            let instruments = instrumentsRaw.compactMap(Instrument.init(rawValue:))
            guard !instruments.isEmpty else {
                return try await fallbackRivalDetail(rivalId: rivalId, visibleInstruments: visibleInstruments)
            }
            return try await combinedRivalDetail(instruments: instruments, rivalId: rivalId)
        case let .combo(token, _):
            return try await rivalComboDetail(token: token, rivalId: rivalId)
        case nil:
            return try await fallbackRivalDetail(rivalId: rivalId, visibleInstruments: visibleInstruments)
        }
    }

    /// Merge every Settings-visible instrument's rivals detail (the fallback path
    /// of `rivalDetail(forScope:rivalId:visibleInstruments:)`).
    private func fallbackRivalDetail(
        rivalId: String, visibleInstruments: [Instrument]
    ) async throws -> RivalDetailResponse {
        guard !visibleInstruments.isEmpty else {
            return .empty(rivalId: rivalId, displayName: nil)
        }
        return try await combinedRivalDetail(instruments: visibleInstruments, rivalId: rivalId)
    }

    /// One instrument's global-leaderboard rivals for the selected player.
    ///
    /// - Parameters:
    ///   - instrument: Solo chart scope.
    ///   - rankBy: Ranking metric.
    /// - Returns: Neighbors on the instrument's global leaderboard.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func leaderboardRivals(
        instrument: Instrument, rankBy: RivalRankMetric = .totalscore
    ) async throws -> LeaderboardRivalsListResponse {
        try await client().leaderboardRivals(
            accountId: requireSelectedAccountId(), instrument: instrument, rankBy: rankBy
        )
    }

    /// One leaderboard rival's head-to-head comparison on one instrument.
    ///
    /// - Parameters:
    ///   - instrument: Solo chart scope.
    ///   - rivalId: Target rival's account ID.
    ///   - rankBy: Ranking metric.
    ///   - sort: `closest`, `they_lead` or `you_lead`.
    /// - Returns: Compared songs for this instrument.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func leaderboardRivalDetail(
        instrument: Instrument, rivalId: String,
        rankBy: RivalRankMetric = .totalscore, sort: String = "closest"
    ) async throws -> RivalDetailResponse {
        try await client().leaderboardRivalDetail(
            accountId: requireSelectedAccountId(), instrument: instrument, rivalId: rivalId,
            rankBy: rankBy, sort: sort
        )
    }
}
