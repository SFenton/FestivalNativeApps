import Foundation

// MARK: - PlayerInstrumentRanking

/// One account's own row on `/api/rankings/{instrument}/{accountId}` — a pure,
/// keyless read (`FSTService/Api/RankingsEndpoints.cs:272`; verified: it only calls
/// `db.GetAccountRanking`/`GetRankedAccountCount`, both in-memory lookups against the
/// precomputed rankings board, never a write). The web client calls the same route as
/// `api.getPlayerRanking` (`FortniteFestivalWeb/src/api/client.ts:514-524`), used from
/// `PlayerPage.tsx:145-154` only as a **fallback** for instruments the player-stats
/// response hasn't embedded canonical ranks for yet.
///
/// This app never calls player-stats at all (`.agents/controls/profile-selection/spec.md`
/// documents its GET as not unconditionally read-only — it can compute and store missing
/// tiers), so every per-instrument global rank shown natively comes from this endpoint.
///
/// The response shares every field of `AccountRankingEntry` (the `/api/rankings/{instrument}`
/// list row) plus `instrument` and `totalRankedAccounts`, so decoding delegates to that
/// type for the common fields instead of duplicating them.
public struct PlayerInstrumentRanking: Decodable, Sendable, Equatable {
    public let entry: AccountRankingEntry
    public let instrument: String
    public let totalRankedAccounts: Int

    private enum CodingKeys: String, CodingKey {
        case instrument, totalRankedAccounts
    }

    /// Decode the flat single-account envelope, reusing `AccountRankingEntry`'s own
    /// field-by-field decoding for everything the list and single-account reads share.
    ///
    /// - Parameter decoder: Raw `/api/rankings/{instrument}/{accountId}` response.
    /// - Throws: Missing or mistyped wire fields.
    public init(from decoder: any Decoder) throws {
        entry = try AccountRankingEntry(from: decoder)
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        instrument = try fields.decode(String.self, forKey: .instrument)
        totalRankedAccounts = try fields.decode(Int.self, forKey: .totalRankedAccounts)
    }

    /// Reject a response for the wrong account/instrument or an impossible total.
    ///
    /// Live-probed 2026-09-28: unlike the list endpoint's `MapAccountRanking` helper
    /// (which falls back to the requested instrument when the DTO's own field is
    /// blank), this single-account route's inline response never applies that
    /// fallback — `instrument` comes back as an empty string in production. An
    /// empty field is therefore accepted (the URL path already scoped the read to
    /// one instrument-specific board); only a **populated but different** value is
    /// rejected as a genuine mismatch.
    ///
    /// - Parameters:
    ///   - instrument: Requested solo chart.
    ///   - accountId: Requested public account key.
    /// - Throws: `FestivalAPIError.invalidLeaderboard` on a mismatched or corrupt response.
    public func validate(instrument: Instrument, accountId: String) throws {
        guard self.instrument.isEmpty || self.instrument == instrument.rawValue,
              entry.accountId.caseInsensitiveCompare(accountId) == .orderedSame,
              totalRankedAccounts >= 0 else {
            throw FestivalAPIError.invalidLeaderboard
        }
    }

    /// A 0-1 fraction where 0 is the very best rank, matching `RankingFormatting.percentile`.
    ///
    /// Adjusted/weighted already carry a native Bayesian percentile
    /// (`AccountRankingEntry.bayesianValue(for:)`); every other metric falls back to a
    /// plain rank-over-field-size fraction, since the wire has no precomputed percentile
    /// for those.
    ///
    /// - Parameter metric: Selected rank-by metric.
    /// - Returns: Nil only when this account has no rank for that metric.
    public func percentile(for metric: RankingMetric) -> Double? {
        if let bayesian = entry.bayesianValue(for: metric) { return bayesian }
        let rank = entry.rank(for: metric)
        guard rank > 0, totalRankedAccounts > 0 else { return nil }
        return Double(rank) / Double(totalRankedAccounts)
    }
}

/// HTTP 404 ("Account not found in rankings for this instrument") is an honest "not
/// ranked yet" state, not a failure — the same shape as `PlayerHistoryState.unregistered`.
public enum PlayerInstrumentRankingState: Sendable, Equatable {
    case available
    case unranked
}

/// A single-account ranking read together with its offline freshness.
public struct PlayerInstrumentRankingPayload: Sendable {
    public let ranking: PlayerInstrumentRanking?
    public let state: PlayerInstrumentRankingState
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

extension FestivalAPI {
    /// Read one account's own row on the per-instrument rankings board.
    ///
    /// - Parameters:
    ///   - instrument: Solo chart to look up.
    ///   - accountId: Validated public account key from a search result or route.
    /// - Returns: The account's rank/rating/percentile, or an explicit unranked state.
    /// - Throws: Invalid parameters, transport failures or malformed wire responses;
    ///   never for an account with no rank on this instrument (see `state`).
    public func playerInstrumentRanking(
        instrument: Instrument, accountId: String
    ) async throws -> PlayerInstrumentRankingPayload {
        guard ProfileSearchText.isValidAccountId(accountId) else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        let resource = PublicEndpoint.playerInstrumentRanking(
            instrument: instrument.rawValue, accountId: accountId
        )
        do {
            let payload = try await read(resource)
            let ranking = try JSONDecoder().decode(PlayerInstrumentRanking.self, from: payload.data)
            try ranking.validate(instrument: instrument, accountId: accountId)
            return PlayerInstrumentRankingPayload(
                ranking: ranking, state: .available,
                publicationId: payload.publicationId,
                observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
            )
        } catch FestivalAPIError.httpStatus(404) {
            let current = try await publication()
            return PlayerInstrumentRankingPayload(
                ranking: nil, state: .unranked, publicationId: nil,
                observedPublicationId: current.publicationId, isStale: false
            )
        } catch is DecodingError {
            throw FestivalAPIError.invalidLeaderboard
        }
    }
}
