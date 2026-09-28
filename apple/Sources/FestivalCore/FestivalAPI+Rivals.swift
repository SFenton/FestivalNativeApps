import Foundation

// MARK: - Rivals endpoint

/// Keyless public Rivals/Compete GETs (`FSTService/Api/RivalsEndpoints.cs`,
/// `LeaderboardRivalsEndpoints.cs`), all confirmed pure reads with
/// `RequireRateLimiting("public")` and no `RequireAuthorization()`: they only
/// read `IMetaDatabase`/`ResponseCacheService` state, never write it. The one
/// side-effecting route in that file, `POST .../rivals/recompute`, is
/// `RequireAuthorization()`-gated and is intentionally never called here.
///
/// These stay unpinned (outside `FestivalAPI.read(_:)`, the Songs/Shop/Player
/// publication-pinned pipeline) because Rivals data is not part of the
/// catalogue/score publication contract that pipeline protects, but they share
/// its transport, keyless header guard and status mapping via `fetchJSON`.
enum RivalsEndpoint: Sendable {
    /// Every combo's rivals with indexed song samples (`/rivals/all`).
    case all(accountId: String)
    case list(accountId: String, instrument: Instrument)
    case comboList(accountId: String, token: String)
    case detail(accountId: String, instrument: Instrument, rivalId: String, sort: String, limit: Int, offset: Int)
    case comboDetail(accountId: String, token: String, rivalId: String, sort: String, limit: Int, offset: Int)
    case leaderboardList(accountId: String, instrument: Instrument, rankBy: RivalRankMetric)
    case leaderboardDetail(
        accountId: String, instrument: Instrument, rivalId: String,
        rankBy: RivalRankMetric, sort: String
    )

    static let validSorts: Set<String> = ["closest", "they_lead", "you_lead"]

    /// Whether a string is a safe path segment for a combo scope: the Pro Drums
    /// family token, or a short lowercase/uppercase hex bitmask
    /// (native `RivalCombo.comboId`/`isHexComboId`).
    ///
    /// - Parameter token: Candidate `RivalComboScope.token`.
    /// - Returns: `true` for `"pro_drums"` or 1–4 hex digits.
    static func isValidComboToken(_ token: String) -> Bool {
        if token == "pro_drums" { return true }
        guard !token.isEmpty, token.count <= 4 else { return false }
        return token.allSatisfy(\.isHexDigit)
    }

    /// Build the request URL for this endpoint.
    ///
    /// - Parameter baseURL: Already-validated HTTPS (or loopback fixture) origin.
    /// - Returns: Fully qualified endpoint URL.
    /// - Throws: `RivalsAPIError.invalidResource` for an untrusted or malformed argument.
    func url(relativeTo baseURL: URL) throws -> URL {
        switch self {
        case let .all(accountId):
            guard ProfileSearchText.isValidAccountId(accountId) else {
                throw RivalsAPIError.invalidResource
            }
            return baseURL
                .appendingPathComponent("api").appendingPathComponent("player")
                .appendingPathComponent(accountId).appendingPathComponent("rivals")
                .appendingPathComponent("all")

        case let .list(accountId, instrument):
            guard ProfileSearchText.isValidAccountId(accountId) else {
                throw RivalsAPIError.invalidResource
            }
            return baseURL
                .appendingPathComponent("api").appendingPathComponent("player")
                .appendingPathComponent(accountId).appendingPathComponent("rivals")
                .appendingPathComponent(instrument.rawValue)

        case let .comboList(accountId, token):
            guard ProfileSearchText.isValidAccountId(accountId), Self.isValidComboToken(token) else {
                throw RivalsAPIError.invalidResource
            }
            return baseURL
                .appendingPathComponent("api").appendingPathComponent("player")
                .appendingPathComponent(accountId).appendingPathComponent("rivals")
                .appendingPathComponent(token)

        case let .detail(accountId, instrument, rivalId, sort, limit, offset):
            guard ProfileSearchText.isValidAccountId(accountId),
                  ProfileSearchText.isValidAccountId(rivalId),
                  Self.validSorts.contains(sort), limit >= 0, offset >= 0 else {
                throw RivalsAPIError.invalidResource
            }
            let path = baseURL
                .appendingPathComponent("api").appendingPathComponent("player")
                .appendingPathComponent(accountId).appendingPathComponent("rivals")
                .appendingPathComponent(instrument.rawValue).appendingPathComponent(rivalId)
            return try Self.appendingQuery(path, [
                ("sort", sort), ("limit", String(limit)), ("offset", String(offset)),
            ])

        case let .comboDetail(accountId, token, rivalId, sort, limit, offset):
            guard ProfileSearchText.isValidAccountId(accountId), Self.isValidComboToken(token),
                  ProfileSearchText.isValidAccountId(rivalId),
                  Self.validSorts.contains(sort), limit >= 0, offset >= 0 else {
                throw RivalsAPIError.invalidResource
            }
            let path = baseURL
                .appendingPathComponent("api").appendingPathComponent("player")
                .appendingPathComponent(accountId).appendingPathComponent("rivals")
                .appendingPathComponent(token).appendingPathComponent(rivalId)
            return try Self.appendingQuery(path, [
                ("sort", sort), ("limit", String(limit)), ("offset", String(offset)),
            ])

        case let .leaderboardList(accountId, instrument, rankBy):
            guard ProfileSearchText.isValidAccountId(accountId) else {
                throw RivalsAPIError.invalidResource
            }
            let path = baseURL
                .appendingPathComponent("api").appendingPathComponent("player")
                .appendingPathComponent(accountId).appendingPathComponent("leaderboard-rivals")
                .appendingPathComponent(instrument.rawValue)
            return try Self.appendingQuery(path, [("rankBy", rankBy.rawValue)])

        case let .leaderboardDetail(accountId, instrument, rivalId, rankBy, sort):
            guard ProfileSearchText.isValidAccountId(accountId),
                  ProfileSearchText.isValidAccountId(rivalId),
                  Self.validSorts.contains(sort) else {
                throw RivalsAPIError.invalidResource
            }
            let path = baseURL
                .appendingPathComponent("api").appendingPathComponent("player")
                .appendingPathComponent(accountId).appendingPathComponent("leaderboard-rivals")
                .appendingPathComponent(instrument.rawValue).appendingPathComponent(rivalId)
            return try Self.appendingQuery(path, [("rankBy", rankBy.rawValue), ("sort", sort)])
        }
    }

    private static func appendingQuery(_ url: URL, _ items: [(String, String)]) throws -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let resolved = components?.url else {
            throw RivalsAPIError.invalidResource
        }
        return resolved
    }
}

extension RivalsEndpoint: ServiceEndpoint {}

extension FestivalAPI {
    /// Fetch and decode one keyless Rivals/Compete GET through the shared,
    /// unpinned request helper (`FestivalAPI+Request.swift`), so Rivals shares
    /// the transport, keyless header guard, timeout and status mapping.
    ///
    /// - Parameters:
    ///   - endpoint: Allowlisted Rivals resource.
    ///   - emptyOn404: Value to substitute for the endpoint's documented
    ///     "no rivals found" / "no precomputed song data" HTTP 404, so callers
    ///     see a normal empty result instead of an error.
    /// - Returns: Decoded response body.
    /// - Throws: `RivalsAPIError` for invalid arguments or undecodable bodies;
    ///   `FestivalAPIError` (including `.publicReadFrozen`) or `URLError` otherwise.
    private func fetchRivalsJSON<T: Decodable & Sendable>(
        _ endpoint: RivalsEndpoint, emptyOn404 emptyValue: T?
    ) async throws -> T {
        do {
            return try await fetchJSON(
                endpoint, as: T.self, invalid: RivalsAPIError.invalidResponse
            ).value
        } catch FestivalAPIError.httpStatus(404) where emptyValue != nil {
            return emptyValue!
        }
    }

    /// Read every combo's rivals in one call
    /// (`GET /api/player/{accountId}/rivals/all`), the source for the web's
    /// `buildRivalDataIndexFromRivalsAll` (`song_rival_*`/`lb_rival_*` suggestions).
    ///
    /// A pure read (`FSTService/Api/RivalsEndpoints.cs:207`): it serves the
    /// precomputed `rivals-all:{accountId}` response, else the in-memory rivals
    /// cache, else `SELECT`s from `user_rivals`/`account_names` and stores the
    /// bytes only in the process response cache. Its HTTP 404 "No rivals found."
    /// becomes an empty response.
    ///
    /// - Parameter accountId: Selected player's account ID.
    /// - Returns: Per-combo rivals plus the song index their samples reference.
    /// - Throws: `RivalsAPIError` for invalid arguments or decoding; shared
    ///   `FestivalAPIError`/`URLError` for HTTP and network failures.
    public func rivalsAll(accountId: String) async throws -> RivalsAllResponse {
        try await fetchRivalsJSON(.all(accountId: accountId), emptyOn404: .empty(accountId: accountId))
    }

    /// Read per-instrument rivals (`GET /api/player/{accountId}/rivals/{instrument}`).
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - instrument: Solo chart scope.
    /// - Returns: Rivals ahead of and behind the player, or an empty list if none exist yet.
    /// - Throws: `RivalsAPIError` for invalid arguments or decoding; shared
    ///   `FestivalAPIError`/`URLError` for HTTP and network failures.
    public func rivalsList(accountId: String, instrument: Instrument) async throws -> RivalsListResponse {
        try await fetchRivalsJSON(
            .list(accountId: accountId, instrument: instrument),
            emptyOn404: .empty(combo: instrument.rawValue)
        )
    }

    /// Read a cross-instrument "combo" or Pro Drums family scope's rivals
    /// (`GET /api/player/{accountId}/rivals/{token}`, `token` a hex combo ID or
    /// `pro_drums`) — a server-computed distinct list, not a client-side merge of
    /// the constituent instruments' own lists.
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - token: `RivalComboScope.token`.
    /// - Returns: Rivals ahead of and behind the player under this scope, or an
    ///   empty list if none exist yet.
    /// - Throws: `RivalsAPIError` for invalid arguments or decoding; shared
    ///   `FestivalAPIError`/`URLError` for HTTP and network failures.
    public func rivalsComboList(accountId: String, token: String) async throws -> RivalsListResponse {
        try await fetchRivalsJSON(
            .comboList(accountId: accountId, token: token), emptyOn404: .empty(combo: token)
        )
    }

    /// Read a rival's shared-song comparison for one instrument
    /// (`GET /api/player/{accountId}/rivals/{instrument}/{rivalId}`).
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - instrument: Solo chart scope.
    ///   - rivalId: Target rival's account ID.
    ///   - sort: `closest`, `they_lead` or `you_lead`.
    ///   - limit: Rows requested; `0` means "all".
    ///   - offset: Zero-based row offset.
    /// - Returns: Compared songs, or an empty detail result if none are precomputed yet.
    /// - Throws: `RivalsAPIError` for invalid arguments or decoding; shared
    ///   `FestivalAPIError`/`URLError` for HTTP and network failures.
    public func rivalDetail(
        accountId: String, instrument: Instrument, rivalId: String,
        sort: String = "closest", limit: Int = 0, offset: Int = 0
    ) async throws -> RivalDetailResponse {
        try await fetchRivalsJSON(
            .detail(
                accountId: accountId, instrument: instrument, rivalId: rivalId,
                sort: sort, limit: limit, offset: offset
            ),
            emptyOn404: .empty(rivalId: rivalId, displayName: nil)
        )
    }

    /// Read a combo/Pro-Drums-family rival's shared-song comparison
    /// (`GET /api/player/{accountId}/rivals/{token}/{rivalId}`).
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - token: `RivalComboScope.token`.
    ///   - rivalId: Target rival's account ID.
    ///   - sort: `closest`, `they_lead` or `you_lead`.
    ///   - limit: Rows requested; `0` means "all".
    ///   - offset: Zero-based row offset.
    /// - Returns: Compared songs, or an empty detail result if none are precomputed yet.
    /// - Throws: `RivalsAPIError` for invalid arguments or decoding; shared
    ///   `FestivalAPIError`/`URLError` for HTTP and network failures.
    public func rivalComboDetail(
        accountId: String, token: String, rivalId: String,
        sort: String = "closest", limit: Int = 0, offset: Int = 0
    ) async throws -> RivalDetailResponse {
        try await fetchRivalsJSON(
            .comboDetail(
                accountId: accountId, token: token, rivalId: rivalId,
                sort: sort, limit: limit, offset: offset
            ),
            emptyOn404: .empty(rivalId: rivalId, displayName: nil)
        )
    }

    /// Read one instrument's global-leaderboard rivals
    /// (`GET /api/player/{accountId}/leaderboard-rivals/{instrument}`).
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - instrument: Solo chart scope.
    ///   - rankBy: Ranking metric.
    /// - Returns: Neighbors on the instrument's global leaderboard.
    /// - Throws: `RivalsAPIError` for invalid arguments or decoding; shared
    ///   `FestivalAPIError`/`URLError` for HTTP and network failures.
    public func leaderboardRivals(
        accountId: String, instrument: Instrument, rankBy: RivalRankMetric = .totalscore
    ) async throws -> LeaderboardRivalsListResponse {
        try await fetchRivalsJSON(
            .leaderboardList(accountId: accountId, instrument: instrument, rankBy: rankBy),
            emptyOn404: nil
        )
    }

    /// Read a leaderboard rival's head-to-head detail
    /// (`GET /api/player/{accountId}/leaderboard-rivals/{instrument}/{rivalId}`).
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - instrument: Solo chart scope.
    ///   - rivalId: Target rival's account ID.
    ///   - rankBy: Ranking metric.
    ///   - sort: `closest`, `they_lead` or `you_lead`.
    /// - Returns: Compared songs for this instrument.
    /// - Throws: `RivalsAPIError` for invalid arguments or decoding; shared
    ///   `FestivalAPIError`/`URLError` for HTTP and network failures.
    public func leaderboardRivalDetail(
        accountId: String, instrument: Instrument, rivalId: String,
        rankBy: RivalRankMetric = .totalscore, sort: String = "closest"
    ) async throws -> RivalDetailResponse {
        try await fetchRivalsJSON(
            .leaderboardDetail(
                accountId: accountId, instrument: instrument, rivalId: rivalId,
                rankBy: rankBy, sort: sort
            ),
            emptyOn404: .empty(rivalId: rivalId, displayName: nil)
        )
    }
}
