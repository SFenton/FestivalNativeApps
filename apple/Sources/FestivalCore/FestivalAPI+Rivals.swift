import Foundation

// MARK: - Rivals endpoint

/// Keyless public Rivals/Compete GETs (`FSTService/Api/RivalsEndpoints.cs`,
/// `LeaderboardRivalsEndpoints.cs`), all confirmed pure reads with
/// `RequireRateLimiting("public")` and no `RequireAuthorization()`: they only
/// read `IMetaDatabase`/`ResponseCacheService` state, never write it. The one
/// side-effecting route in that file, `POST .../rivals/recompute`, is
/// `RequireAuthorization()`-gated and is intentionally never called here.
///
/// These bypass `FestivalAPI.read(_:)` (the Songs/Shop/Player publication-pinned
/// pipeline) because Rivals data is not part of the catalogue/score publication
/// contract that pipeline exists to protect; it is fetched directly against
/// `FestivalAPI.baseURL` with the same keyless, no-cache request shape.
enum RivalsEndpoint: Sendable {
    case list(accountId: String, instrument: Instrument)
    case detail(accountId: String, instrument: Instrument, rivalId: String, sort: String, limit: Int, offset: Int)
    case leaderboardList(accountId: String, instrument: Instrument, rankBy: RivalRankMetric)
    case leaderboardDetail(
        accountId: String, instrument: Instrument, rivalId: String,
        rankBy: RivalRankMetric, sort: String
    )

    static let validSorts: Set<String> = ["closest", "they_lead", "you_lead"]

    /// Build the request URL for this endpoint.
    ///
    /// - Parameter baseURL: Already-validated HTTPS (or loopback fixture) origin.
    /// - Returns: Fully qualified endpoint URL.
    /// - Throws: `RivalsAPIError.invalidResource` for an untrusted or malformed argument.
    func url(relativeTo baseURL: URL) throws -> URL {
        switch self {
        case let .list(accountId, instrument):
            guard ProfileSearchText.isValidAccountId(accountId) else {
                throw RivalsAPIError.invalidResource
            }
            return baseURL
                .appendingPathComponent("api").appendingPathComponent("player")
                .appendingPathComponent(accountId).appendingPathComponent("rivals")
                .appendingPathComponent(instrument.rawValue)

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

/// Ephemeral, no-cache transport for keyless Rivals reads; a static member on
/// an extension is allowed to be stored (unlike an instance property), so this
/// adds no state to `FestivalAPI` itself.
private let rivalsHTTPSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
}()

extension FestivalAPI {
    /// Fetch and decode one keyless Rivals/Compete GET.
    ///
    /// - Parameters:
    ///   - endpoint: Allowlisted Rivals resource.
    ///   - emptyOn404: Value to substitute for the endpoint's documented
    ///     "no rivals found" / "no precomputed song data" HTTP 404, so callers
    ///     see a normal empty result instead of an error.
    /// - Returns: Decoded response body.
    /// - Throws: `RivalsAPIError` for network, HTTP or decoding failures.
    private func fetchRivalsJSON<T: Decodable>(
        _ endpoint: RivalsEndpoint, emptyOn404 emptyValue: T?
    ) async throws -> T {
        let url = try endpoint.url(relativeTo: baseURL)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await rivalsHTTPSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw RivalsAPIError.invalidResponse
        }
        if http.statusCode == 404, let emptyValue {
            return emptyValue
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 503 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                throw RivalsAPIError.unavailable(retryAfter: retryAfter)
            }
            throw RivalsAPIError.httpStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RivalsAPIError.invalidResponse
        }
    }

    /// Read per-instrument rivals (`GET /api/player/{accountId}/rivals/{instrument}`).
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - instrument: Solo chart scope.
    /// - Returns: Rivals ahead of and behind the player, or an empty list if none exist yet.
    /// - Throws: `RivalsAPIError` for network, HTTP or decoding failures.
    public func rivalsList(accountId: String, instrument: Instrument) async throws -> RivalsListResponse {
        try await fetchRivalsJSON(
            .list(accountId: accountId, instrument: instrument),
            emptyOn404: .empty(combo: instrument.rawValue)
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
    /// - Throws: `RivalsAPIError` for network, HTTP or decoding failures.
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

    /// Read one instrument's global-leaderboard rivals
    /// (`GET /api/player/{accountId}/leaderboard-rivals/{instrument}`).
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - instrument: Solo chart scope.
    ///   - rankBy: Ranking metric.
    /// - Returns: Neighbors on the instrument's global leaderboard.
    /// - Throws: `RivalsAPIError` for network, HTTP or decoding failures.
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
    /// - Throws: `RivalsAPIError` for network, HTTP or decoding failures.
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
