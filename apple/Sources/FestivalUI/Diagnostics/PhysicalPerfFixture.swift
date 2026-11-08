#if DEBUG && os(iOS)
import Foundation
import Network

// MARK: - Physical benchmark fixtures

/// Replays an immutable synthetic wire archive on device loopback, only in isolated
/// benchmark bundles. Neither the public client nor its origin/read gates change.
@MainActor
enum PhysicalPerfFixture {
    private static var server: Server?

    /// Starts the requested fixture before either app creates its public client.
    ///
    /// - Parameter environment: Explicit benchmark launch environment.
    /// - Throws: Invalid archive, non-benchmark identity, origin mismatch or bind failure.
    static func startIfRequested(environment: [String: String]) throws {
        guard let filename = environment["FST_PERF_FIXTURE_ARCHIVE"] else { return }
        guard ["com.sfenton.festivalscoretracker.perf.swiftui",
               "com.sfenton.festivalscoretracker.perf.uikit"].contains(Bundle.main.bundleIdentifier ?? ""),
              environment["FST_PERF_AUTORUN"] != nil,
              filename == "fst-physical-fixture.json" else { throw FixtureError.invalidArchive }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: documents.appendingPathComponent(filename)))
        guard archive.schema == 1, archive.origin == environment["FST_API_BASE_URL"],
              let origin = URLComponents(string: archive.origin), origin.scheme == "http",
              origin.host == "127.0.0.1", origin.path.isEmpty, origin.query == nil,
              origin.user == nil, origin.password == nil, origin.fragment == nil,
              let number = origin.port, (1024...65535).contains(number),
              let port = NWEndpoint.Port(rawValue: UInt16(number)) else { throw FixtureError.invalidArchive }
        let instance = try Server(archive: archive, port: port)
        try instance.start()
        server = instance
    }

    /// Numeric replay evidence; an unrecorded read is never a successful empty fixture.
    static var summary: String {
        "fixture_active=\(server == nil ? 0 : 1) fixture_reads=\(server?.reads ?? 0) fixture_misses=\(server?.misses ?? 0)"
    }

    private enum FixtureError: Error { case invalidArchive, bindFailed }

    private struct Archive: Decodable, Sendable {
        let schema: Int
        let origin: String
        let responses: [String: Response]
    }

    private struct Response: Decodable, Sendable {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    // Listener/connection work is confined to queue; cross-queue counters use lock.
    private final class Server: @unchecked Sendable {
        private let archive: Archive
        private let listener: NWListener
        private let missingRequestsFile: URL
        private let queue = DispatchQueue(label: "fst.physical-perf.fixture")
        private let lock = NSLock()
        private var readCount = 0
        private var missCount = 0
        private var ready = false

        var reads: Int { lock.withLock { readCount } }
        var misses: Int { lock.withLock { missCount } }

        init(archive: Archive, port: NWEndpoint.Port) throws {
            self.archive = archive
            missingRequestsFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("fst-physical-missing-requests.txt")
            try Data().write(to: missingRequestsFile)
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            listener = try NWListener(using: parameters)
        }

        func start() throws {
            let completion = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.lock.withLock { self?.ready = true }
                    completion.signal()
                case .failed, .cancelled:
                    completion.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.receive(connection, accumulated: Data())
            }
            listener.start(queue: queue)
            guard completion.wait(timeout: .now() + 5) == .success,
                  lock.withLock({ ready }) else {
                listener.cancel()
                throw FixtureError.bindFailed
            }
        }

        private func receive(_ connection: NWConnection, accumulated: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
                guard let self, error == nil else { connection.cancel(); return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                guard bytes.count <= 16_384 else { connection.cancel(); return }
                if let boundary = bytes.range(of: Data("\r\n\r\n".utf8)),
                   let text = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) {
                    self.respond(connection, request: text)
                } else if complete {
                    connection.cancel()
                } else {
                    self.receive(connection, accumulated: bytes)
                }
            }
        }

        private func respond(_ connection: NWConnection, request: String) {
            let lines = request.components(separatedBy: "\r\n")
            let first = (lines.first ?? "").split(separator: " ")
            let forbidden = lines.dropFirst().contains {
                let name = $0.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
                return name == "x-api-key" || name.hasPrefix("x-fst-selected-")
            }
            guard first.count == 3, first[0] == "GET", !forbidden,
                  first[1].hasPrefix("/"), !first[1].hasPrefix("//"),
                  var components = URLComponents(string: String(first[1])),
                  components.scheme == nil, components.host == nil, components.fragment == nil else {
                send(connection, response: Response(status: 405, headers: [:], body: Data()))
                return
            }
            if let query = components.percentEncodedQuery {
                components.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%20")
            }
            let pairs = (components.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" }.sorted()
            guard !components.path.contains("\n"), !pairs.contains(where: { $0.contains("\n") }) else {
                send(connection, response: Response(status: 400, headers: [:], body: Data()))
                return
            }
            let key = ([components.path] + pairs).joined(separator: "\n")
            lock.withLock { readCount += 1 }
            guard let response = archive.responses[key] else {
                lock.withLock { missCount += 1 }
                if let handle = try? FileHandle(forWritingTo: missingRequestsFile) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: Data("\(first[1])\n".utf8))
                }
                send(connection, response: Response(status: 404, headers: [:], body: Data()))
                return
            }
            send(connection, response: response)
        }

        private func send(_ connection: NWConnection, response: Response) {
            let excluded = ["content-length", "connection", "transfer-encoding", "date", "server"]
            let headers = response.headers.sorted { $0.key < $1.key }.compactMap { key, value -> String? in
                guard !excluded.contains(key.lowercased()),
                      !key.contains("\r"), !key.contains("\n"), !key.contains(":"),
                      !value.contains("\r"), !value.contains("\n") else { return nil }
                return "\(key): \(value)\r\n"
            }.joined()
            var bytes = Data(("HTTP/1.1 \(response.status) Fixture\r\n" + headers
                              + "Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n").utf8)
            bytes.append(response.body)
            connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
#endif
