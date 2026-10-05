import Foundation

/// A typed subset of service reads available without the privileged API key.
public enum PublicEndpoint: Sendable {
    case songs
    case shop
    case player(accountId: String)
    case playerHistory(accountId: String, songId: String? = nil, instrument: String? = nil)
    case playerNotifications(accountId: String, limit: Int = 50)
    case leaderboard(
        songId: String, instrument: String, top: Int = 25, offset: Int = 0, leeway: Double? = nil
    )
    case rankings(instrument: String, rankBy: String, page: Int, pageSize: Int)
    /// One account's own row on the per-instrument rankings board
    /// (`GET /api/rankings/{instrument}/{accountId}`) — the pure-read fallback the
    /// web client uses when its player-stats read hasn't embedded canonical ranks
    /// yet (see `PlayerInstrumentRanking.swift`); never the player-stats GET itself,
    /// which can compute and store missing tiers.
    case playerInstrumentRanking(instrument: String, accountId: String)
    /// Daily Total Score/skill rank snapshots for one account on one instrument
    /// (`PlayerRankHistory.swift`); a pure `SELECT`, unlike player-stats.
    case playerRankHistory(instrument: String, accountId: String, days: Int)
    case bandRankings(bandType: String, rankBy: String, page: Int, pageSize: Int)
    case playerBands(accountId: String, group: String, page: Int, pageSize: Int)
    case playerBandsByType(accountId: String, bandType: String, combo: String?)
    /// One team's ranking row via the same pure-read rankings board as
    /// `bandRankings`, never `/api/bands/{bandId}` (see `FestivalAPI+Bands.swift`
    /// for why that endpoint is not called).
    case bandProfile(bandType: String, teamKey: String, combo: String?)
    case bandRankHistory(bandType: String, teamKey: String, combo: String?, days: Int)
    case bandSongExtremes(bandType: String, teamKey: String, combo: String?, limit: Int)
    /// One page of a song's band leaderboard
    /// (`GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=[&combo=][&accountId=]`).
    /// `accountId` is a query parameter that only asks for the selected player's best
    /// band row (`selectedPlayerEntry`); it is never a selected-profile header.
    case songBandLeaderboard(
        songId: String, bandType: String, top: Int, offset: Int, combo: String?, accountId: String? = nil
    )
    /// Song Detail's band previews: every band size's top rows in one pure read
    /// (`GET /api/leaderboard/{songId}/bands/all?top=[&accountId=]`). `accountId` is a
    /// query parameter that only asks for the selected player's best band row; it is
    /// never a selected-profile header.
    case songBandLeaderboards(songId: String, top: Int, accountId: String?)
    case path(
        songId: String, instrument: Instrument, difficulty: PathDifficulty,
        display: PathDisplayMode, generationId: String? = nil
    )

    /// Build a URL from individually encoded path segments.
    ///
    /// - Parameter baseURL: HTTPS service origin or a loopback fixture server.
    /// - Returns: Valid endpoint URL.
    /// - Throws: Invalid resource or player identifier errors.
    func url(relativeTo baseURL: URL) throws -> URL {
        let segments: [String]
        var query: [URLQueryItem] = []
        switch self {
        case .songs:
            segments = ["api", "songs"]
        case .shop:
            segments = ["api", "shop"]
        case let .player(accountId):
            guard ProfileSearchText.isValidAccountId(accountId) else {
                throw FestivalAPIError.invalidPlayerProfile
            }
            segments = ["api", "player", accountId]
        case let .playerHistory(accountId, songId, instrument):
            guard ProfileSearchText.isValidAccountId(accountId) else {
                throw FestivalAPIError.invalidPlayerProfile
            }
            if let songId, songId.isEmpty || songId.contains("/") {
                throw FestivalAPIError.invalidResource
            }
            if let instrument, instrument.isEmpty || instrument.contains("/") {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "player", accountId, "history"]
            if let songId { query.append(URLQueryItem(name: "songId", value: songId)) }
            if let instrument { query.append(URLQueryItem(name: "instrument", value: instrument)) }
        case let .playerNotifications(accountId, limit):
            guard ProfileSearchText.isValidAccountId(accountId), (1...200).contains(limit) else {
                throw FestivalAPIError.invalidPlayerProfile
            }
            segments = ["api", "player", accountId, "notifications"]
            query = [URLQueryItem(name: "limit", value: String(limit))]
        case let .leaderboard(songId, instrument, top, offset, leeway):
            guard !songId.isEmpty, !instrument.isEmpty,
                  !songId.contains("/"), !instrument.contains("/"),
                  top > 0, offset >= 0 else {
                throw FestivalAPIError.invalidResource
            }
            if let leeway, (!leeway.isFinite || !(-5...5).contains(leeway)) {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "leaderboard", songId, instrument]
            query = [
                URLQueryItem(name: "top", value: String(top)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            if let leeway {
                query.append(URLQueryItem(name: "leeway", value: String(leeway)))
            }
        case let .rankings(instrument, rankBy, page, pageSize):
            guard !instrument.isEmpty, !instrument.contains("/"),
                  !rankBy.isEmpty, !rankBy.contains("/"),
                  page > 0, (1...200).contains(pageSize) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "rankings", instrument]
            query = [
                URLQueryItem(name: "rankBy", value: rankBy),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
            ]
        case let .playerInstrumentRanking(instrument, accountId):
            guard !instrument.isEmpty, !instrument.contains("/"),
                  ProfileSearchText.isValidAccountId(accountId) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "rankings", instrument, accountId]
        case let .playerRankHistory(instrument, accountId, days):
            guard !instrument.isEmpty, !instrument.contains("/"),
                  ProfileSearchText.isValidAccountId(accountId), (1...365).contains(days) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "rankings", instrument, accountId, "history"]
            query = [URLQueryItem(name: "days", value: String(days))]
        case let .bandRankings(bandType, rankBy, page, pageSize):
            guard !bandType.isEmpty, !bandType.contains("/"),
                  !rankBy.isEmpty, !rankBy.contains("/"),
                  page > 0, (1...200).contains(pageSize) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "rankings", "bands", bandType]
            query = [
                URLQueryItem(name: "rankBy", value: rankBy),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
            ]
        case let .playerBands(accountId, group, page, pageSize):
            guard ProfileSearchText.isValidAccountId(accountId),
                  ["all", "duos", "trios", "quads"].contains(group),
                  page > 0, (1...100).contains(pageSize) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "player", accountId, "bands"]
            query = [
                URLQueryItem(name: "group", value: group),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
            ]
        case let .playerBandsByType(accountId, bandType, combo):
            guard ProfileSearchText.isValidAccountId(accountId),
                  !bandType.isEmpty, !bandType.contains("/"),
                  Self.isValidCombo(combo) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "player", accountId, "bands", bandType]
            query = combo.map { [URLQueryItem(name: "combo", value: $0)] } ?? []
        case let .bandProfile(bandType, teamKey, combo):
            guard !bandType.isEmpty, !bandType.contains("/"),
                  !teamKey.isEmpty, !teamKey.contains("/"),
                  Self.isValidCombo(combo) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "rankings", "bands", bandType]
            query = [
                URLQueryItem(name: "teamKey", value: teamKey),
                URLQueryItem(name: "rankBy", value: "adjusted"),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "pageSize", value: "1"),
            ]
            if let combo { query.append(URLQueryItem(name: "combo", value: combo)) }
        case let .bandRankHistory(bandType, teamKey, combo, days):
            guard !bandType.isEmpty, !bandType.contains("/"),
                  !teamKey.isEmpty, !teamKey.contains("/"),
                  (1...3650).contains(days), Self.isValidCombo(combo) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "rankings", "bands", bandType, teamKey, "history"]
            query = [URLQueryItem(name: "days", value: String(days))]
            if let combo { query.append(URLQueryItem(name: "combo", value: combo)) }
        case let .bandSongExtremes(bandType, teamKey, combo, limit):
            guard !bandType.isEmpty, !bandType.contains("/"),
                  !teamKey.isEmpty, !teamKey.contains("/"),
                  (1...20).contains(limit), Self.isValidCombo(combo) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "rankings", "bands", bandType, teamKey, "songs"]
            query = [URLQueryItem(name: "limit", value: String(limit))]
            if let combo { query.append(URLQueryItem(name: "combo", value: combo)) }
        case let .songBandLeaderboard(songId, bandType, top, offset, combo, accountId):
            guard !songId.isEmpty, !songId.contains("/"),
                  !bandType.isEmpty, !bandType.contains("/"),
                  (1...100).contains(top), offset >= 0, Self.isValidCombo(combo),
                  accountId.map(ProfileSearchText.isValidAccountId) ?? true else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "leaderboard", songId, "bands", bandType]
            query = [
                URLQueryItem(name: "top", value: String(top)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            if let combo { query.append(URLQueryItem(name: "combo", value: combo)) }
            if let accountId { query.append(URLQueryItem(name: "accountId", value: accountId)) }
        case let .songBandLeaderboards(songId, top, accountId):
            guard !songId.isEmpty, !songId.contains("/"), (1...50).contains(top),
                  accountId.map(ProfileSearchText.isValidAccountId) ?? true else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "leaderboard", songId, "bands", "all"]
            query = [URLQueryItem(name: "top", value: String(top))]
            if let accountId { query.append(URLQueryItem(name: "accountId", value: accountId)) }
        case let .path(songId, instrument, difficulty, display, generationId):
            guard !songId.isEmpty, !songId.contains("/"), !songId.contains(".."),
                  instrument != .karaoke,
                  generationId == nil || (
                    !(generationId?.isEmpty ?? true)
                    && (generationId?.count ?? 0) <= 200
                  ) else {
                throw FestivalAPIError.invalidResource
            }
            segments = ["api", "paths", songId, instrument.rawValue, difficulty.rawValue]
                + (display == .text ? ["data"] : [])
            if let generationId {
                query = [URLQueryItem(name: "generationId", value: generationId)]
            }
        }
        let url = segments.reduce(baseURL) { url, segment in
            url.appendingPathComponent(segment)
        }
        if query.isEmpty { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let resolved = components?.url else {
            throw FestivalAPIError.invalidResource
        }
        return resolved
    }

    /// Whether HTTP 202 is a documented syncing envelope rather than an error.
    ///
    /// - Returns: True for a player profile or score history still being synced.
    var acceptsSyncing: Bool {
        switch self {
        case .player, .playerHistory: true
        default: false
        }
    }

    /// Keep personal profile bytes out of the raw multi-resource cache.
    ///
    /// - Returns: False for account profiles, including HTTP 202 syncing envelopes,
    ///   for a player's own bands list (also account-scoped) and for band previews
    ///   or band leaderboard pages that carry a selected player's `accountId`.
    var allowsSnapshotCache: Bool {
        switch self {
        case .player, .playerHistory, .playerNotifications, .playerBands, .playerBandsByType,
             .playerInstrumentRanking, .playerRankHistory:
            false
        case let .songBandLeaderboards(_, _, accountId):
            accountId == nil
        case let .songBandLeaderboard(_, _, _, _, _, accountId):
            accountId == nil
        default: true
        }
    }

    /// Reject an empty or path-breaking combo filter without over-constraining it,
    /// since valid combo identifiers are server-defined (e.g. `"GB"`, `"GV"`).
    ///
    /// - Parameter combo: Optional instrument-combo filter.
    /// - Returns: True when absent or a plausible single path segment.
    private static func isValidCombo(_ combo: String?) -> Bool {
        guard let combo else { return true }
        return !combo.isEmpty && !combo.contains("/")
    }
}

/// Direct keyless reads without client publication pinning or an offline snapshot.
public enum OperationalEndpoint: Sendable {
    case features
    case accountSearch(query: String, limit: Int)

    /// Resolve a known operational path without attaching selected-profile metadata.
    ///
    /// - Parameter baseURL: Configured service origin.
    /// - Returns: Public operational endpoint URL with bounded search arguments.
    /// - Throws: Profile search query or limit validation errors.
    func url(relativeTo baseURL: URL) throws -> URL {
        switch self {
        case .features:
            return baseURL.appendingPathComponent("api").appendingPathComponent("features")
        case let .accountSearch(query, limit):
            guard (2...200).contains(query.count),
                  query == query.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ProfileSearchText.containsUnsafeScalar(query)
            else {
                throw FestivalAPIError.invalidProfileSearchQuery
            }
            guard (1...10).contains(limit) else {
                throw FestivalAPIError.invalidProfileSearchLimit
            }
            var components = URLComponents(
                url: baseURL.appendingPathComponent("api")
                    .appendingPathComponent("account").appendingPathComponent("search"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
            let encodedQuery = components?.percentEncodedQuery
            components?.percentEncodedQuery = encodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
            guard let url = components?.url else {
                throw FestivalAPIError.invalidProfileSearchQuery
            }
            return url
        }
    }
}

/// Explicit synthetic public-read states restricted to loopback development.
public enum FixtureScenario: String, Sendable {
    case demo
    case empty
    case error
    case shopEmpty = "shop-empty"
    case shopError = "shop-error"
    case shopSingle = "shop-single"
    case artError = "art-error"
    case artSkip = "art-skip"
    case artWhite = "art-white"
}

/// Platform-neutral response shape that can be substituted by fixture transports.
public struct HTTPResult: Sendable {
    public let status: Int
    public let data: Data
    private let headers: [String: String]

    /// Normalizes response header names to case-insensitive lookups.
    ///
    /// - Parameters:
    ///   - status: HTTP response status.
    ///   - data: Unmodified wire payload.
    ///   - headers: Response headers in any capitalization.
    public init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { _, replacement in replacement }
        )
    }

    /// Read a response header without depending on the server's capitalization.
    ///
    /// - Parameter name: Header name as written in the service contract.
    /// - Returns: Header value, if present.
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// An injectable async HTTP transport with no implicit persistence.
public protocol HTTPTransport: Sendable {
    /// Send an HTTP request and return the raw response.
    ///
    /// - Parameter request: URLSession-compatible request.
    /// - Returns: Status, headers and bytes without model expansion.
    func send(_ request: URLRequest) async throws -> HTTPResult
}

/// Production URLSession transport that explicitly bypasses the platform cache.
public struct URLSessionHTTPTransport: HTTPTransport {
    /// Internal so the feedback upload (`FestivalAPI+Feedback.swift`) reuses this session.
    let session: URLSession

    /// Create a transport with neither a disk nor an in-memory HTTP cache.
    public init() {
        self.init(protocolClasses: [])
    }

    /// Allow test-only URL protocols without changing production cache policy.
    ///
    /// - Parameter protocolClasses: Custom URLProtocol implementations for fixture tests.
    init(protocolClasses: [AnyClass]) {
        let configuration = URLSessionConfiguration.ephemeral
        if !protocolClasses.isEmpty {
            configuration.protocolClasses = protocolClasses
        }
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// Fetch bytes from the service over HTTPS or a loopback fixture endpoint.
    ///
    /// - Parameter request: Service request.
    /// - Returns: HTTP status, payload and normalized response headers.
    /// - Throws: `FestivalAPIError.invalidResponse` if the server is not HTTP.
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw FestivalAPIError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String, let value = pair.value as? String else {
                return
            }
            result[key] = value
        }
        return HTTPResult(status: response.statusCode, data: data, headers: headers)
    }
}

/// Bytes together with the origin and freshness that the UI must disclose.
public struct PublicPayload: Sendable {
    public let data: Data
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
    public let httpStatus: Int

    /// Create a payload with an explicit offline/stale indicator.
    ///
    /// - Parameters:
    ///   - data: Wire response bytes.
    ///   - publicationId: Response-proven generation, or nil for unpinned bytes.
    ///   - observedPublicationId: Validated bootstrap generation during the read,
    ///     not a claim that unpinned bytes came from that generation.
    ///   - isStale: True only when the network failed and a memory copy was used.
    ///   - httpStatus: Actual successful HTTP result, or 200 for retained cached data.
    public init(
        data: Data, publicationId: Int?, observedPublicationId: Int,
        isStale: Bool, httpStatus: Int = 200
    ) {
        self.data = data
        self.publicationId = publicationId
        self.observedPublicationId = observedPublicationId
        self.isStale = isStale
        self.httpStatus = httpStatus
    }
}

/// Publication-aware, read-only API client for distributable native apps.
public actor FestivalAPI {
    let baseURL: URL
    let transport: any HTTPTransport
    private let cache: SessionResponseCache
    private let fixtureScenario: FixtureScenario?
    private var current: Publication?

    /// Create a service client without obtaining or retaining any privileged key.
    ///
    /// - Parameters:
    ///   - baseURL: HTTPS production origin, or loopback HTTP for local fixtures.
    ///   - fixtureScenario: Optional loopback-only Songs state for UI automation.
    ///   - transport: Injected transport; defaults to URLSession.
    ///   - cache: Process-lifetime cache shared across warm app resumes.
    /// - Throws: `FestivalAPIError.insecureBaseURL` for other cleartext origins.
    public init(
        baseURL: URL = URL(string: "https://festivalscoretracker.com")!,
        fixtureScenario: FixtureScenario? = nil,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        cache: SessionResponseCache = SessionResponseCache()
    ) throws {
        let loopback = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        guard baseURL.scheme == "https" || (loopback && baseURL.scheme == "http") else {
            throw FestivalAPIError.insecureBaseURL
        }
        guard fixtureScenario == nil || (loopback && baseURL.scheme == "http") else {
            throw FestivalAPIError.invalidResource
        }
        self.baseURL = baseURL
        self.fixtureScenario = fixtureScenario
        self.transport = transport
        self.cache = cache
    }

    // MARK: - Publication consistency

    /// Bootstrap or refresh the service's current published generation.
    ///
    /// - Parameter force: Ignore the last generation when handling a 409 conflict.
    /// - Returns: Validated publication information.
    /// - Throws: Network, HTTP, decoding or publication validation failures.
    public func publication(force: Bool = false) async throws -> Publication {
        if !force, let current {
            return current
        }
        let response = try await send(Self.makeRequest(
            baseURL.appendingPathComponent("api").appendingPathComponent("publication")
        ))
        guard try Self.mapStatus(response, acceptsSyncing: false) == .success,
              response.status == 200 else {
            throw FestivalAPIError.httpStatus(response.status)
        }
        let new = try JSONDecoder().decode(Publication.self, from: response.data)
        try new.validate()
        if let current, new.publicationId < current.publicationId {
            throw FestivalAPIError.invalidPublication
        }
        if current?.publicationId != new.publicationId {
            current = new
            await cache.removeAll()
        } else {
            current = new
        }
        guard current?.publicationId == new.publicationId else {
            throw FestivalAPIError.invalidPublication
        }
        return new
    }

    /// Read allowlisted GETs without a client publication pin or offline cache.
    ///
    /// - Parameter endpoint: Allowlisted direct-read path.
    /// - Returns: Wire bytes never treated as an offline snapshot.
    /// - Throws: Network or HTTP errors, including Retry-After on a service 503.
    public func readOperational(_ endpoint: OperationalEndpoint) async throws -> Data {
        try await fetch(endpoint, acceptsSyncing: true).value
    }

    /// Fetch a public resource, retrying one publication conflict and safe ETags.
    ///
    /// - Parameter endpoint: Allowlisted public resource, never an admin route.
    /// - Returns: Wire payload tagged with publication and offline freshness.
    /// - Throws: Network, HTTP and generation-consistency errors.
    public func read(_ endpoint: PublicEndpoint) async throws -> PublicPayload {
        let url = try resourceURL(for: endpoint)
        for attempt in 0..<2 {
            let generation = try await publication()
            do {
                return try await readOnce(url, generation: generation, endpoint: endpoint)
            } catch FestivalAPIError.invalidPublication where attempt == 0 {
                if current?.publicationId == generation.publicationId {
                    _ = try await publication(force: true)
                }
            }
        }
        throw FestivalAPIError.invalidPublication
    }

    /// Resolve one canonical URL for both the live request and its validated snapshot.
    ///
    /// - Parameter endpoint: Allowlisted public resource with paging and fixture query.
    /// - Returns: Exact cache key and URL requested from the public service.
    /// - Throws: Invalid resource components or URL encoding.
    func resourceURL(for endpoint: PublicEndpoint) throws -> URL {
        let resourceURL = try endpoint.url(relativeTo: baseURL)
        var components = URLComponents(url: resourceURL, resolvingAgainstBaseURL: false)
        switch endpoint {
        case .songs, .shop:
            if let fixtureScenario {
                components?.queryItems = [
                    URLQueryItem(name: "scenario", value: fixtureScenario.rawValue)
                ]
            }
        default:
            break
        }
        guard let url = components?.url else {
            throw FestivalAPIError.invalidResource
        }
        return url
    }

    /// Retain only a typed, validated headerless payload as explicitly unverified.
    ///
    /// - Parameters:
    ///   - payload: Public bytes after the endpoint-specific wire model passed validation.
    ///   - endpoint: Exact allowlisted resource including all cache-key query arguments.
    /// - Throws: Cancellation or a publication changed while validation was completing.
    func rememberUnverified(
        _ payload: PublicPayload, for endpoint: PublicEndpoint
    ) async throws {
        guard endpoint.allowsSnapshotCache else {
            throw FestivalAPIError.invalidResource
        }
        guard payload.publicationId == nil, !payload.isStale else { return }
        try Task.checkCancellation()
        guard let active = current,
              active.publicationId == payload.observedPublicationId,
              !(active.readyForPinning && active.pinningEnabled) else {
            throw FestivalAPIError.invalidPublication
        }
        let resource = try resourceURL(for: endpoint).absoluteString
        await cache.storeUnverified(
            .init(data: payload.data, observedPublicationId: payload.observedPublicationId),
            for: resource
        )
        guard let latest = current,
              latest.publicationId == payload.observedPublicationId,
              !(latest.readyForPinning && latest.pinningEnabled) else {
            await cache.removeUnverified(
                for: resource, observedPublicationId: payload.observedPublicationId
            )
            try Task.checkCancellation()
            throw FestivalAPIError.invalidPublication
        }
        try Task.checkCancellation()
    }

    /// Execute one bounded generation attempt without returning obsolete data.
    ///
    /// - Parameters:
    ///   - url: Fully qualified public resource, including pagination arguments.
    ///   - generation: Publication observed before starting this attempt.
    ///   - endpoint: Typed endpoint controlling path-image cache and byte limits.
    /// - Returns: Verified or explicitly unpinned response bytes.
    /// - Throws: Inconsistent generations, network or HTTP failures.
    private func readOnce(
        _ url: URL, generation: Publication, endpoint: PublicEndpoint
    ) async throws -> PublicPayload {
        var publication = generation
        let identifier = url.absoluteString
        var cached: SessionResponseCache.Entry?
        if endpoint.allowsSnapshotCache {
            cached = await cache.entry(for: identifier, publicationId: publication.publicationId)
        }
        var response: HTTPResult
        do {
            response = try await send(
                request(for: url, publication: publication, etag: cached?.etag)
            )
        } catch let error as URLError {
            try Task.checkCancellation()
            if error.canUseOfflineCache,
               current?.publicationId == publication.publicationId {
                if let cached {
                    return PublicPayload(
                        data: cached.data, publicationId: publication.publicationId,
                        observedPublicationId: publication.publicationId, isStale: true
                    )
                }
                if let current, !(current.readyForPinning && current.pinningEnabled),
                   let snapshot = await cache.unverifiedSnapshot(
                    for: identifier, observedPublicationId: publication.publicationId
                ) {
                    try Task.checkCancellation()
                    guard let active = self.current,
                          active.publicationId == publication.publicationId,
                          !(active.readyForPinning && active.pinningEnabled) else {
                        throw FestivalAPIError.invalidPublication
                    }
                    return PublicPayload(
                        data: snapshot.data, publicationId: nil,
                        observedPublicationId: publication.publicationId, isStale: true
                    )
                }
            }
            throw error
        }
        guard current?.publicationId == publication.publicationId else {
            throw FestivalAPIError.invalidPublication
        }

        if response.status == 409,
           (try? JSONDecoder().decode(Conflict.self, from: response.data))?.status
                == "publication_changed" {
            publication = try await self.publication(force: true)
            if endpoint.allowsSnapshotCache {
                cached = await cache.entry(
                    for: identifier, publicationId: publication.publicationId
                )
            }
            response = try await send(
                request(for: url, publication: publication, etag: cached?.etag)
            )
            guard current?.publicationId == publication.publicationId else {
                throw FestivalAPIError.invalidPublication
            }
        }

        if response.status == 304 {
            let responseId = Int(response.header("X-FST-Publication-Id") ?? "")
            if let cached,
               cached.publicationId == publication.publicationId,
               responseId == publication.publicationId,
               current?.publicationId == publication.publicationId {
                return PublicPayload(
                    data: cached.data, publicationId: publication.publicationId,
                    observedPublicationId: publication.publicationId, isStale: false
                )
            }
            response = try await send(
                request(for: url, publication: publication, etag: nil)
            )
            if response.status == 304 {
                throw FestivalAPIError.unexpectedNotModified
            }
        }

        let status = try Self.mapStatus(response, acceptsSyncing: endpoint.acceptsSyncing)
        switch endpoint {
        case .player where response.data.count > PlayerProfileResponse.wireByteLimit:
            throw FestivalAPIError.invalidPlayerProfile
        case .shop where response.data.count > 4_000_000:
            throw FestivalAPIError.invalidShop
        case let .path(_, _, _, display, _) where response.data.count > 8_000_000:
            throw display == .image
                ? FestivalAPIError.invalidPathImage : FestivalAPIError.invalidPathData
        default:
            break
        }
        let responseId = Int(response.header("X-FST-Publication-Id") ?? "")
        if let responseId, responseId != publication.publicationId {
            guard !publication.pinningEnabled, responseId > publication.publicationId else {
                throw FestivalAPIError.invalidPublication
            }
            let advanced = try await self.publication(force: true)
            guard advanced.publicationId == responseId else {
                throw FestivalAPIError.invalidPublication
            }
            publication = advanced
        }
        guard current?.publicationId == publication.publicationId else {
            throw FestivalAPIError.invalidPublication
        }
        if status == .syncing {
            try Task.checkCancellation()
            return PublicPayload(
                data: response.data, publicationId: responseId,
                observedPublicationId: publication.publicationId,
                isStale: false, httpStatus: 202
            )
        }
        if responseId != nil {
            try Task.checkCancellation()
            if endpoint.allowsSnapshotCache {
                let entry = SessionResponseCache.Entry(
                    data: response.data,
                    publicationId: publication.publicationId,
                    etag: response.header("ETag")
                )
                if case let .path(_, _, _, display, _) = endpoint, display == .image {
                    try await cache.storePathImageIfActive(entry, for: identifier)
                } else {
                    try await cache.storeIfActive(entry, for: identifier)
                }
                do {
                    try Task.checkCancellation()
                    guard current?.publicationId == publication.publicationId else {
                        throw FestivalAPIError.invalidPublication
                    }
                } catch {
                    await cache.removeVerifiedIfMatching(entry, for: identifier)
                    throw error
                }
            }
        } else if publication.readyForPinning && publication.pinningEnabled {
            throw FestivalAPIError.invalidPublication
        }
        try Task.checkCancellation()
        return PublicPayload(
            data: response.data, publicationId: responseId,
            observedPublicationId: publication.publicationId,
            isStale: false, httpStatus: response.status
        )
    }

    /// Build a pinned request without allowing URLSession to serve stale browser-style cache.
    ///
    /// - Parameters:
    ///   - url: Allowlisted endpoint URL.
    ///   - publication: Generation observed before this request.
    ///   - etag: Optional entity tag for a matching cached generation.
    /// - Returns: Configured HTTP GET request.
    private func request(for url: URL, publication: Publication, etag: String?) -> URLRequest {
        var request = Self.makeRequest(url)
        if publication.readyForPinning && publication.pinningEnabled {
            request.setValue(
                String(publication.publicationId), forHTTPHeaderField: "X-FST-Publication-Id"
            )
        }
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }
}

/// Minimal conflict wire shape; other 409 responses do not trigger a retry.
private struct Conflict: Decodable {
    let status: String
}
