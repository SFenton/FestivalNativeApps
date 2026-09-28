#if os(macOS)
import Foundation

/// Process the `atexit` handler below can reach without capturing context.
///
/// `atexit(_:)` only accepts a plain C function pointer, so the process handle
/// has to live in a global rather than being captured by a closure.
private nonisolated(unsafe) var fst_rivalsMockProcess: Process?

/// Registered once: stop the fixture server on process exit.
///
/// `swift test` (via `swift-testing`'s parallel runner) commonly ends the test
/// process with `SIGTERM` rather than letting `main` return, so both a plain
/// `atexit` (the graceful-exit case) and `SIGTERM`/`SIGINT` handlers (the common
/// case) are registered; a `SIGKILL` still leaves the child running, same as any
/// other test tool that shells out to a subprocess.
private let fst_registerRivalsMockCleanup: Void = {
    atexit {
        fst_rivalsMockProcess?.terminate()
    }
    signal(SIGTERM) { _ in
        fst_rivalsMockProcess?.terminate()
        _exit(143)
    }
    signal(SIGINT) { _ in
        fst_rivalsMockProcess?.terminate()
        _exit(130)
    }
}()

/// Failure starting the shared loopback fixture server.
enum RivalsMockServiceError: Error {
    case timedOut
    case unreadableOutput
}

/// Launches `tools/mock_service.py` as a real loopback process for the Rivals/
/// Compete hosted snapshot tests, and reuses it for every test in the process.
///
/// Every other domain's hosted tests substitute an in-memory `HTTPTransport`
/// actor (see `HostedRankingsTransport`/`HostedHistoryTransport`). That doesn't
/// work here: `FestivalAPI+Rivals.swift` documents that Rivals reads
/// intentionally bypass the injectable `HTTPTransport` pipeline and issue real
/// `URLSession` requests straight at `FestivalAPI.baseURL`, because Rivals data
/// isn't part of the publication-pinned contract `FestivalAPI.read(_:)`
/// protects. A `URLSessionConfiguration` with no custom `protocolClasses` can't
/// be intercepted by a registered `URLProtocol` either (that only affects the
/// legacy `NSURLConnection` loading system). The only reliable, product-code-free
/// fixture is a genuine loopback origin — exactly what `AGENTS.md` already
/// requires for fixture-backed tests — so this starts the same fixture server
/// the XCUITest journeys use (`tools/mock_service.py`, extended with Rivals/
/// Compete routes), asks the OS for a free port (`--port 0`), and reads back the
/// bound port from its "Local test fixture service on 127.0.0.1:<port>" line.
actor RivalsMockService {
    static let shared = RivalsMockService()

    private var resolvedBaseURL: URL?
    private var startTask: Task<URL, Error>?

    private init() {}

    /// The running fixture server's loopback origin.
    ///
    /// Starts the process on first use; every later caller in this test
    /// process (including concurrent Swift Testing runs) awaits the same
    /// launch rather than starting a second server.
    ///
    /// - Returns: `http://127.0.0.1:<port>`, valid for the rest of the process.
    /// - Throws: `RivalsMockServiceError` if the server never printed its ready line.
    func baseURL() async throws -> URL {
        if let resolvedBaseURL { return resolvedBaseURL }
        if let startTask {
            return try await startTask.value
        }
        let task = Task<URL, Error> { try await Self.launch() }
        startTask = task
        do {
            let url = try await task.value
            resolvedBaseURL = url
            return url
        } catch {
            startTask = nil
            throw error
        }
    }

    private static func launch() async throws -> URL {
        _ = fst_registerRivalsMockCleanup
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.currentDirectoryURL = repoRoot
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tools/mock_service.py", "--port", "0"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        fst_rivalsMockProcess = process

        let handle = stdout.fileHandleForReading
        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                let data = handle.availableData
                guard let text = String(data: data, encoding: .utf8),
                      let port = Self.parsePort(from: text) else {
                    throw RivalsMockServiceError.unreadableOutput
                }
                return URL(string: "http://127.0.0.1:\(port)")!
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw RivalsMockServiceError.timedOut
            }
            guard let result = try await group.next() else {
                throw RivalsMockServiceError.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    private static func parsePort(from line: String) -> Int? {
        guard let range = line.range(of: "127.0.0.1:") else { return nil }
        let rest = line[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        return Int(digits)
    }
}
#endif
