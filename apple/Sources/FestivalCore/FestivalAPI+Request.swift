import Foundation

// MARK: - Endpoint descriptor

/// Any allowlisted keyless GET that the shared request helper can resolve.
///
/// `PublicEndpoint` (publication-pinned), `OperationalEndpoint` and
/// `RivalsEndpoint` (both unpinned) conform. Add a new read by adding a case to
/// one of them; never create another `URLSession`.
protocol ServiceEndpoint: Sendable {
    /// Build the request URL from individually validated segments.
    ///
    /// - Parameter baseURL: Validated HTTPS or loopback fixture origin.
    /// - Returns: Fully qualified endpoint URL.
    /// - Throws: A domain `invalidResource`-style error for untrusted arguments.
    func url(relativeTo baseURL: URL) throws -> URL
}

extension PublicEndpoint: ServiceEndpoint {}
extension OperationalEndpoint: ServiceEndpoint {}

// MARK: - Response

/// A successful unpinned read plus the provenance headers the helper observed.
public struct ServiceResponse<Value: Sendable>: Sendable {
    /// Decoded body, or raw bytes for `Data` reads.
    public let value: Value
    /// 2xx status; 202 only when the endpoint accepts a syncing envelope.
    public let httpStatus: Int
    /// `X-FST-Publication-Id` from the response, when the service sent one.
    public let publicationId: Int?
    /// Bootstrap generation observed before the read, when observation was requested.
    public let observedPublicationId: Int?
    /// `X-FST-Public-Read-Freeze-Reason`, present on successful reads served during a freeze.
    public let freezeReason: String?
}

// MARK: - Status mapping

/// How a response status should be interpreted by the caller.
enum ServiceStatus: Equatable, Sendable {
    /// 2xx other than an accepted 202: decode the body.
    case success
    /// Accepted HTTP 202 syncing envelope.
    case syncing
}

// MARK: - Request helper

extension FestivalAPI {
    /// Idle timeout for every service request.
    static let requestTimeout: TimeInterval = 30

    /// Header names that must never leave the app (compared case-insensitively).
    static let forbiddenHeaderNames: Set<String> = ["x-api-key"]
    /// Header prefixes that must never leave the app: selected-profile headers
    /// register activity even on cached GETs (see `service-safety.md`).
    static let forbiddenHeaderPrefixes = ["x-fst-selected-"]

    /// Build the one keyless GET shape every service read uses.
    ///
    /// - Parameter url: Allowlisted endpoint URL.
    /// - Returns: A no-cache GET with the shared timeout and no credentials.
    static func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout
        )
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    /// Reject a request carrying a privileged key or selected-profile header.
    ///
    /// - Parameter request: Request about to be sent.
    /// - Throws: `FestivalAPIError.forbiddenRequestHeader` if any header is unsafe.
    static func validateKeyless(_ request: URLRequest) throws {
        for name in (request.allHTTPHeaderFields ?? [:]).keys {
            let lowered = name.lowercased()
            if forbiddenHeaderNames.contains(lowered)
                || forbiddenHeaderPrefixes.contains(where: lowered.hasPrefix) {
                throw FestivalAPIError.forbiddenRequestHeader
            }
        }
        guard request.httpMethod == nil || request.httpMethod == "GET" else {
            throw FestivalAPIError.forbiddenRequestHeader
        }
    }

    /// Map a response status onto the shared error vocabulary.
    ///
    /// - Parameters:
    ///   - response: Raw transport result.
    ///   - acceptsSyncing: Whether this endpoint documents a 202 syncing envelope.
    /// - Returns: `.success` for 2xx, or `.syncing` for an accepted 202.
    /// - Throws: `.syncing` for an unexpected 202, `.unexpectedNotModified` for a
    ///   stray 304, `.publicReadFrozen` or `.unavailable` for 503, otherwise `.httpStatus`.
    static func mapStatus(_ response: HTTPResult, acceptsSyncing: Bool) throws -> ServiceStatus {
        switch response.status {
        case 202:
            guard acceptsSyncing else { throw FestivalAPIError.syncing }
            return .syncing
        case 200...299:
            return .success
        case 304:
            throw FestivalAPIError.unexpectedNotModified
        case 503:
            let retryAfter = response.header("Retry-After")
            if let reason = response.header(ServiceFreezeReason.header), !reason.isEmpty {
                throw FestivalAPIError.publicReadFrozen(reason: reason, retryAfter: retryAfter)
            }
            throw FestivalAPIError.unavailable(retryAfter: retryAfter)
        default:
            throw FestivalAPIError.httpStatus(response.status)
        }
    }

    /// Send one request through the single transport gate.
    ///
    /// Every service GET, pinned or not, passes here: the gate enforces the
    /// keyless header rule and checks cancellation on both sides of the wire.
    ///
    /// - Parameter request: Request built by `makeRequest(_:)`, optionally with
    ///   publication pin or `If-None-Match` headers added.
    /// - Returns: Raw status, headers and bytes.
    /// - Throws: `CancellationError`, `forbiddenRequestHeader` or transport errors.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        try Self.validateKeyless(request)
        try Task.checkCancellation()
        let response = try await transport.send(request)
        try Task.checkCancellation()
        return response
    }

    /// Read an unpinned endpoint's raw bytes through the shared helper.
    ///
    /// - Parameters:
    ///   - endpoint: Allowlisted keyless GET.
    ///   - acceptsSyncing: Whether a 202 envelope is a valid result.
    ///   - observesPublication: Bootstrap `/api/publication` first and report it.
    /// - Returns: Bytes with status, response publication and freeze reason.
    /// - Throws: Endpoint validation, transport, cancellation or mapped status errors.
    func fetch(
        _ endpoint: some ServiceEndpoint,
        acceptsSyncing: Bool = false,
        observesPublication: Bool = false
    ) async throws -> ServiceResponse<Data> {
        let url = try endpoint.url(relativeTo: baseURL)
        let observed = observesPublication ? try await publication().publicationId : nil
        let response = try await send(Self.makeRequest(url))
        _ = try Self.mapStatus(response, acceptsSyncing: acceptsSyncing)
        return ServiceResponse(
            value: response.data,
            httpStatus: response.status,
            publicationId: Int(response.header("X-FST-Publication-Id") ?? ""),
            observedPublicationId: observed,
            freezeReason: response.header(ServiceFreezeReason.header)
        )
    }

    /// Read and decode an unpinned JSON endpoint through the shared helper.
    ///
    /// - Parameters:
    ///   - endpoint: Allowlisted keyless GET.
    ///   - type: Wire model to decode.
    ///   - invalid: Domain error thrown when the body does not decode.
    ///   - acceptsSyncing: Whether a 202 envelope is a valid result.
    ///   - observesPublication: Bootstrap `/api/publication` first and report it.
    /// - Returns: Decoded value with status and provenance headers.
    /// - Throws: Endpoint validation, transport, mapped status or `invalid`.
    func fetchJSON<T: Decodable & Sendable>(
        _ endpoint: some ServiceEndpoint,
        as type: T.Type,
        invalid: any Error = FestivalAPIError.invalidResponse,
        acceptsSyncing: Bool = false,
        observesPublication: Bool = false
    ) async throws -> ServiceResponse<T> {
        let raw = try await fetch(
            endpoint, acceptsSyncing: acceptsSyncing, observesPublication: observesPublication
        )
        let value: T
        do {
            value = try JSONDecoder().decode(T.self, from: raw.value)
        } catch {
            throw invalid
        }
        return ServiceResponse(
            value: value, httpStatus: raw.httpStatus, publicationId: raw.publicationId,
            observedPublicationId: raw.observedPublicationId, freezeReason: raw.freezeReason
        )
    }
}

// MARK: - Debug forced freeze

/// Debug-only transport decorator that answers the first request to each
/// `/api/…` path with a synthetic scrape-freeze 503 (`Retry-After: 30`,
/// `X-FST-Public-Read-Freeze-Reason: scrape`), then passes through.
///
/// Enabled by `FST_DEBUG_FORCE_FREEZE=1` so the "Scores are updating" state can
/// be screenshotted without waiting for a real scrape. `/api/publication` is
/// never frozen so each screen shows exactly one freeze for its own read.
public actor ForcedFreezeTransport: HTTPTransport {
    private let wrapped: any HTTPTransport
    private let retryAfter: String
    private var frozenPaths: Set<String> = []

    /// Wrap a real transport.
    ///
    /// - Parameters:
    ///   - wrapped: Transport used after each path's single synthetic freeze.
    ///   - retryAfter: `Retry-After` value to synthesize.
    public init(wrapping wrapped: any HTTPTransport, retryAfter: String = "30") {
        self.wrapped = wrapped
        self.retryAfter = retryAfter
    }

    /// Return a synthetic freeze once per API path, otherwise forward the request.
    ///
    /// - Parameter request: Outgoing request.
    /// - Returns: Synthetic 503 or the wrapped transport's result.
    /// - Throws: Whatever the wrapped transport throws.
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        if path.hasPrefix("/api/"), path != "/api/publication",
           frozenPaths.insert(path).inserted {
            return HTTPResult(
                status: 503,
                data: Data(#"{"title":"Published data unavailable","status":503}"#.utf8),
                headers: [
                    "Retry-After": retryAfter,
                    ServiceFreezeReason.header: "scrape",
                    "Cache-Control": "no-store",
                ]
            )
        }
        return try await wrapped.send(request)
    }
}
