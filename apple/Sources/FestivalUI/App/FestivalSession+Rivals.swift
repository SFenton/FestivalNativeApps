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

    /// One scope's shared-song comparison against a rival, sent in the web's
    /// `getRivalDetail` shape (`limit=0&sort=closest[&allowLiveFallback=true]`).
    ///
    /// - Parameters:
    ///   - token: A solo instrument raw value, hex combo ID or `pro_drums`.
    ///   - rivalId: Target rival's account ID.
    ///   - allowLiveFallback: Whether the service may compute samples for an
    ///     untracked rival (read-only; web Find Rival).
    /// - Returns: Compared songs for this scope.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func rivalScopeDetail(
        token: String, rivalId: String, allowLiveFallback: Bool = false
    ) async throws -> RivalDetailResponse {
        let accountId = try requireSelectedAccountId()
        if let instrument = RivalDetailScopes.soloInstrument(forToken: token) {
            return try await client().rivalDetail(
                accountId: accountId, instrument: instrument, rivalId: rivalId,
                allowLiveFallback: allowLiveFallback
            )
        }
        return try await client().rivalComboDetail(
            accountId: accountId, token: token, rivalId: rivalId, allowLiveFallback: allowLiveFallback
        )
    }

    /// A rival's comparison merged across one or more scopes, ported from the
    /// web's `fetchCombinedRivalDetail`: a failed scope is dropped, and the read
    /// throws only when every scope failed.
    ///
    /// - Parameters:
    ///   - scopes: Scope tokens from `RivalDetailScopes.tokens(for:visible:)`.
    ///   - rivalId: Target rival's account ID.
    ///   - allowLiveFallback: Passed to every scope read.
    /// - Returns: The union of compared songs across the scopes.
    /// - Throws: No selected player, or the first scope's failure when all failed.
    func combinedRivalDetail(
        scopes: [String], rivalId: String, allowLiveFallback: Bool = false
    ) async throws -> RivalDetailResponse {
        var unique: [String] = []
        for scope in scopes where !unique.contains(scope) { unique.append(scope) }
        guard !unique.isEmpty else { throw FestivalAPIError.invalidResource }
        // Sequential rather than concurrent: at most three scopes, and this keeps
        // every call on the session's MainActor isolation.
        var succeeded: [RivalDetailResponse] = []
        var firstError: Error?
        for scope in unique {
            do {
                succeeded.append(try await rivalScopeDetail(
                    token: scope, rivalId: rivalId, allowLiveFallback: allowLiveFallback
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        guard let merged = RivalDetailResponse.combined(succeeded, scopes: unique) else {
            throw firstError ?? FestivalAPIError.invalidResponse
        }
        return merged
    }

    /// Resolve a rival detail read for a typed `RivalScope`, with the same scope
    /// and query as the web (`RivalDetailScopes`), so the app reuses
    /// the responses the service keeps for the web during a publish.
    ///
    /// Shared by `RivalDetailScreen`, `RivalryScreen` and the dual-screen
    /// rivalry pane, so a pushed `AppRoute.rivalDetail`/`.rivalry` resolves its
    /// optional scope identically. If the detail endpoint answers 503 while the
    /// service publishes, the comparison is rebuilt from the precomputed
    /// `/rivals/all` samples (`RivalDetailFallback`). When that response has
    /// nothing for this rival, the original error is rethrown for the retry state.
    ///
    /// - Parameters:
    ///   - scope: The route's carried scope, or `nil` (Find Rival, deep link).
    ///   - rivalId: Target rival's account ID.
    ///   - visibleInstruments: Settings-visible instruments, used to derive the
    ///     Settings scope(s) for Common Rivals and `nil` scopes.
    /// - Returns: Compared songs for the resolved scope.
    /// - Throws: No selected player, or a `RivalsAPIError`/transport failure.
    func rivalDetail(
        forScope scope: RivalScope?, rivalId: String, visibleInstruments: [Instrument]
    ) async throws -> RivalDetailResponse {
        if case let .leaderboard(instrumentRaw, rankBy) = scope,
           let instrument = Instrument(rawValue: instrumentRaw) {
            return try await leaderboardRivalDetail(instrument: instrument, rivalId: rivalId, rankBy: rankBy)
        }
        let scopes = RivalDetailScopes.tokens(for: scope, visible: visibleInstruments)
        do {
            return try await combinedRivalDetail(
                scopes: scopes, rivalId: rivalId,
                allowLiveFallback: RivalDetailScopes.allowsLiveFallback(for: scope)
            )
        } catch let error as FestivalAPIError {
            switch error {
            case .publicReadFrozen, .unavailable:
                if let fallback = await publishFallbackDetail(rivalId: rivalId, scopes: scopes) {
                    return fallback
                }
            default:
                break
            }
            throw error
        }
    }

    /// Rebuild a detail from `/rivals/all` while the detail endpoint is frozen.
    ///
    /// - Parameters:
    ///   - rivalId: Target rival's account ID.
    ///   - scopes: Scope tokens the detail read asked for.
    /// - Returns: The rebuilt detail, or `nil` when unavailable.
    private func publishFallbackDetail(rivalId: String, scopes: [String]) async -> RivalDetailResponse? {
        guard let accountId = try? requireSelectedAccountId(),
              let all = try? await client().rivalsAll(accountId: accountId) else {
            return nil
        }
        let songs = (try? await catalog())?.catalog.songs ?? []
        let info = Dictionary(
            songs.map { ($0.songId, (title: $0.title, artist: $0.artist)) },
            uniquingKeysWith: { first, _ in first }
        )
        return RivalDetailFallback.detail(from: all, rivalId: rivalId, scopes: scopes) { info[$0] }
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
