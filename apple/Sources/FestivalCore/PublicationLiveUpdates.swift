import Foundation

// MARK: - Live publication updates (issue #304)

/// One server message on the public `/api/ws` socket, reduced to what the apps act on.
///
/// The web's `useAppWebSocket.ts` holds one anonymous socket to
/// `/api/ws?publicationId=N` and re-reads `/api/publication` when the server sends
/// `{"type":"publication_changed"}`. Everything else (the `shop_snapshot` sent on connect,
/// Shop rotation, account sync messages that an anonymous socket never receives) is
/// ignored here; the apps keep reading the Item Shop over HTTPS.
public enum PublicationLiveMessage: Equatable, Sendable {
    /// The service published a new generation (`publicationId` when the server sent one).
    case publicationChanged(Int?)
    /// Any other or malformed message.
    case other

    /// Decode one text frame without trusting its shape.
    ///
    /// - Parameter data: UTF-8 JSON frame bytes.
    /// - Returns: ``publicationChanged(_:)`` for a `publication_changed` object, else ``other``.
    public static func parse(_ data: Data) -> PublicationLiveMessage {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "publication_changed" else {
            return .other
        }
        let id = (object["publicationId"] as? NSNumber).flatMap { number -> Int? in
            let value = number.intValue
            return value > 0 && Double(value) == number.doubleValue ? value : nil
        }
        return .publicationChanged(id)
    }
}

/// Reconnect delays matching the web socket: 1 s, doubling, at most 30 s; reset once a
/// connection opens.
public struct PublicationLiveBackoff: Equatable, Sendable {
    /// First reconnect delay (web `INITIAL_RETRY_MS`).
    public static let initial: Duration = .seconds(1)
    /// Longest reconnect delay (web `MAX_RETRY_MS`).
    public static let maximum: Duration = .seconds(30)

    private var nextDelay: Duration = Self.initial

    /// Start at the initial delay.
    public init() {}

    /// The delay before the next attempt, doubling the one after it.
    ///
    /// - Returns: The current delay.
    public mutating func next() -> Duration {
        let delay = nextDelay
        nextDelay = min(nextDelay * 2, Self.maximum)
        return delay
    }

    /// A connection opened: the next failure retries after the initial delay again.
    public mutating func reset() {
        nextDelay = Self.initial
    }
}

/// What a live socket reports to ``PublicationLiveUpdates/run(refresh:url:connect:sleep:)``.
public enum PublicationSocketEvent: Equatable, Sendable {
    /// The WebSocket handshake completed.
    case opened
    /// One text (or binary) frame.
    case message(Data)
}

/// Opens the public live socket. Injectable so the loop is testable without a network.
public protocol PublicationLiveSocket: Sendable {
    /// Connect and report events until the server closes (stream finishes) or the
    /// connection fails (stream throws). Cancelling the consuming task closes the socket.
    ///
    /// - Parameter url: The `wss://…/api/ws?publicationId=N` URL.
    /// - Returns: The connection's events.
    func connect(to url: URL) -> AsyncThrowingStream<PublicationSocketEvent, any Error>
}

// MARK: - URLSession socket

/// The production socket: `URLSessionWebSocketTask` on an ephemeral, cache-free session.
///
/// It sends no frames and no custom headers: never an `X-API-Key`, never a
/// selected-profile header and never `subscribe_sync` (which binds a socket to an
/// account). The service registers an anonymous connection in memory only
/// (`.agents/platforms/service-safety.md`, `/api/ws`).
public struct URLSessionPublicationLiveSocket: PublicationLiveSocket {
    /// Largest accepted frame: the connect-time `shop_snapshot` is ~35 KB today, with
    /// generous room for a larger Shop.
    public static let maximumMessageSize = 8_000_000

    private let session: URLSession

    /// Create a socket factory with its own ephemeral session.
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    public func connect(to url: URL) -> AsyncThrowingStream<PublicationSocketEvent, any Error> {
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = Self.maximumMessageSize
        return AsyncThrowingStream { continuation in
            let reader = Task {
                task.resume()
                var opened = false
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        if !opened {
                            opened = true
                            continuation.yield(.opened)
                        }
                        switch message {
                        case let .string(text): continuation.yield(.message(Data(text.utf8)))
                        case let .data(data): continuation.yield(.message(data))
                        @unknown default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    // A server close surfaces as a receive error; both end this connection.
                    if opened, task.closeCode != .invalid {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}

// MARK: - URL

extension FestivalAPI {
    /// Whether this client reads a loopback fixture server rather than the public service.
    public nonisolated var usesLoopbackOrigin: Bool {
        ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
    }

    /// The public live socket for this client's origin (`wss` for HTTPS, `ws` only for a
    /// loopback fixture server).
    ///
    /// - Parameter publicationId: The generation the app currently shows.
    /// - Returns: `…/api/ws?publicationId=N`.
    /// - Throws: `FestivalAPIError.invalidResource` for an unusable origin or ID.
    public nonisolated func liveUpdatesURL(publicationId: Int) throws -> URL {
        guard publicationId > 0,
              var components = URLComponents(
                url: baseURL.appendingPathComponent("api").appendingPathComponent("ws"),
                resolvingAgainstBaseURL: false
              ) else {
            throw FestivalAPIError.invalidResource
        }
        switch components.scheme {
        case "https": components.scheme = "wss"
        case "http" where usesLoopbackOrigin: components.scheme = "ws"
        default: throw FestivalAPIError.invalidResource
        }
        components.queryItems = [URLQueryItem(name: "publicationId", value: String(publicationId))]
        guard let url = components.url else { throw FestivalAPIError.invalidResource }
        return url
    }
}

// MARK: - Loop

/// The live publication loop, like the web's `useAppWebSocket`.
public enum PublicationLiveUpdates {
    /// Keep a live socket open until the calling task is cancelled.
    ///
    /// Each round re-reads the publication (`refresh`, which also lets the app observe a
    /// new generation), then connects with that generation. A `publication_changed`
    /// message starts the next round at once, so the app refreshes without any user
    /// action. A closed or failed connection waits ``PublicationLiveBackoff`` first (reset
    /// after a connection that opened). A second `publication_changed` for a generation
    /// that did not advance also waits, without resetting the backoff, so a misbehaving
    /// server cannot cause a tight loop.
    ///
    /// - Parameters:
    ///   - refresh: Re-reads `/api/publication` and returns the observed generation.
    ///   - url: Builds the socket URL for a generation.
    ///   - connect: Opens the socket.
    ///   - sleep: Waits between attempts; throws when cancelled.
    public static func run(
        refresh: @escaping @Sendable () async throws -> Int,
        url: @escaping @Sendable (Int) throws -> URL,
        connect: @escaping @Sendable (URL) -> AsyncThrowingStream<PublicationSocketEvent, any Error>,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async {
        var backoff = PublicationLiveBackoff()
        var lastChanged: Int?
        while !Task.isCancelled {
            var publicationId: Int?
            var opened = false
            var changed = false
            do {
                let current = try await refresh()
                publicationId = current
                try Task.checkCancellation()
                for try await event in connect(try url(current)) {
                    switch event {
                    case .opened:
                        opened = true
                    case let .message(data):
                        if case .publicationChanged = PublicationLiveMessage.parse(data) { changed = true }
                    }
                    if changed { break }
                }
            } catch {
                if Task.isCancelled { return }
            }
            if Task.isCancelled { return }
            let repeated = changed && publicationId != nil && lastChanged == publicationId
            lastChanged = changed ? publicationId : nil
            if changed && !repeated {
                backoff.reset()
                continue
            }
            if opened && !repeated { backoff.reset() }
            do { try await sleep(backoff.next()) } catch { return }
        }
    }
}
