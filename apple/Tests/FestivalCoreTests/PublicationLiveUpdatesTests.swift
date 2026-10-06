import Foundation
import Testing
@testable import FestivalCore

// MARK: - Live publication updates (issue #304)

/// Records what the live loop did, for scripted runs.
private actor LiveRecorder {
    private(set) var connected: [URL] = []
    private(set) var sleeps: [Duration] = []
    private var refreshes: [Int]
    private var refreshIndex = 0

    init(refreshes: [Int]) { self.refreshes = refreshes }

    func refresh() -> Int {
        let id = refreshes[min(refreshIndex, refreshes.count - 1)]
        refreshIndex += 1
        return id
    }

    func connect(_ url: URL) -> Int {
        connected.append(url)
        return connected.count
    }

    /// - Returns: False once `limit` waits happened, which stops the loop.
    func sleep(_ duration: Duration, limit: Int) -> Bool {
        sleeps.append(duration)
        return sleeps.count < limit
    }
}

/// A scripted stream: the given events, then a close or a failure.
private func stream(
    _ events: [PublicationSocketEvent], failing: Bool = false
) -> AsyncThrowingStream<PublicationSocketEvent, any Error> {
    AsyncThrowingStream { continuation in
        events.forEach { continuation.yield($0) }
        if failing {
            continuation.finish(throwing: URLError(.cannotConnectToHost))
        } else {
            continuation.finish()
        }
    }
}

private let changed = PublicationSocketEvent.message(Data(#"{"type":"publication_changed","publicationId":8}"#.utf8))
private let snapshot = PublicationSocketEvent.message(Data(#"{"type":"shop_snapshot","songs":[]}"#.utf8))

/// Run the loop until `sleepLimit` waits, with scripted publications and connections.
private func runLoop(
    refreshes: [Int], sleepLimit: Int,
    connection: @escaping @Sendable (Int) -> AsyncThrowingStream<PublicationSocketEvent, any Error>
) async throws -> LiveRecorder {
    let recorder = LiveRecorder(refreshes: refreshes)
    let client = try FestivalAPI()
    await PublicationLiveUpdates.run(
        refresh: { await recorder.refresh() },
        url: { try client.liveUpdatesURL(publicationId: $0) },
        connect: { url in
            // The connection number decides the script.
            let box = AsyncThrowingStream<PublicationSocketEvent, any Error> { continuation in
                Task {
                    let number = await recorder.connect(url)
                    do {
                        for try await event in connection(number) { continuation.yield(event) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            return box
        },
        sleep: { duration in
            guard await recorder.sleep(duration, limit: sleepLimit) else { throw CancellationError() }
        }
    )
    return recorder
}

@Suite("PublicationLiveUpdates")
struct PublicationLiveUpdatesTests {
    @Test("only publication_changed frames matter; malformed frames are ignored")
    func parsesMessages() {
        #expect(PublicationLiveMessage.parse(Data(#"{"type":"publication_changed","publicationId":432}"#.utf8))
            == .publicationChanged(432))
        #expect(PublicationLiveMessage.parse(Data(#"{"type":"publication_changed"}"#.utf8)) == .publicationChanged(nil))
        #expect(PublicationLiveMessage.parse(Data(#"{"type":"publication_changed","publicationId":-3}"#.utf8))
            == .publicationChanged(nil))
        #expect(PublicationLiveMessage.parse(Data(#"{"type":"shop_snapshot","songs":[]}"#.utf8)) == .other)
        #expect(PublicationLiveMessage.parse(Data("not json".utf8)) == .other)
        #expect(PublicationLiveMessage.parse(Data("[1,2]".utf8)) == .other)
    }

    @Test("reconnects back off 1 s, doubling to 30 s, and reset after a connection opens")
    func backoff() {
        var backoff = PublicationLiveBackoff()
        let delays = (0..<7).map { _ in backoff.next() }
        #expect(delays == [1, 2, 4, 8, 16, 30, 30].map { Duration.seconds($0) })
        backoff.reset()
        #expect(backoff.next() == .seconds(1))
    }

    @Test("the socket URL follows the client's origin and never carries credentials")
    func socketURL() throws {
        let live = try FestivalAPI()
        #expect(!live.usesLoopbackOrigin)
        #expect(try live.liveUpdatesURL(publicationId: 431).absoluteString
            == "wss://festivalscoretracker.com/api/ws?publicationId=431")
        let fixture = try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:8787")!)
        #expect(fixture.usesLoopbackOrigin)
        #expect(try fixture.liveUpdatesURL(publicationId: 7).absoluteString
            == "ws://127.0.0.1:8787/api/ws?publicationId=7")
        #expect(throws: FestivalAPIError.self) { try live.liveUpdatesURL(publicationId: 0) }
    }

    @Test("publication_changed re-reads the publication and reconnects at once")
    func changeRefreshesImmediately() async throws {
        let recorder = try await runLoop(refreshes: [7, 8], sleepLimit: 1) { number in
            number == 1 ? stream([.opened, snapshot, changed]) : stream([.opened, snapshot])
        }
        #expect(await recorder.connected.map(\.absoluteString) == [
            "wss://festivalscoretracker.com/api/ws?publicationId=7",
            "wss://festivalscoretracker.com/api/ws?publicationId=8",
        ])
        #expect(await recorder.sleeps == [.seconds(1)], "only the plain close of the second socket waits")
    }

    @Test("failed connections retry with growing delays")
    func failuresBackOff() async throws {
        let recorder = try await runLoop(refreshes: [7], sleepLimit: 4) { _ in stream([], failing: true) }
        #expect(await recorder.sleeps == [1, 2, 4, 8].map { Duration.seconds($0) })
        #expect(await recorder.connected.count == 4)
    }

    @Test("an opened connection resets the delay after it closes")
    func openResetsBackoff() async throws {
        let recorder = try await runLoop(refreshes: [7], sleepLimit: 3) { number in
            number == 2 ? stream([.opened]) : stream([], failing: true)
        }
        #expect(await recorder.sleeps == [1, 1, 2].map { Duration.seconds($0) })
    }

    @Test("a repeated change for a publication that did not advance waits and backs off")
    func repeatedChangeBacksOff() async throws {
        let recorder = try await runLoop(refreshes: [7], sleepLimit: 2) { _ in stream([.opened, changed]) }
        #expect(await recorder.connected.count == 3)
        #expect(await recorder.sleeps == [1, 2].map { Duration.seconds($0) })
    }

    @Test("cancelling the task stops the loop")
    func cancellationStops() async throws {
        let client = try FestivalAPI()
        let task = Task {
            await PublicationLiveUpdates.run(
                refresh: { 7 },
                url: { try client.liveUpdatesURL(publicationId: $0) },
                connect: { _ in AsyncThrowingStream { _ in } },
                sleep: { try await Task.sleep(for: $0) }
            )
        }
        task.cancel()
        await task.value
    }
}
