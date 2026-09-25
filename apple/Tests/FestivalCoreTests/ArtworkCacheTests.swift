import Foundation
import Testing
@testable import FestivalCore

/// Simulate a transport that finishes an old image after its publication changes.
private actor DelayedArtworkTransport: HTTPTransport {
    private var sends = 0
    private var suspended: CheckedContinuation<HTTPResult, Error>?
    private var waiting: CheckedContinuation<Void, Never>?

    /// Delay the first image, then serve a different byte sequence.
    ///
    /// - Parameter request: Ephemeral artwork request.
    /// - Returns: Original or replacement fixture bytes.
    /// - Throws: Invalid requests outside the synthetic artwork URL.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.url?.path == "/fixture.png" else {
            throw FestivalAPIError.invalidResource
        }
        sends += 1
        if sends == 1 {
            return try await withCheckedThrowingContinuation { continuation in
                suspended = continuation
                waiting?.resume()
                waiting = nil
            }
        }
        return HTTPResult(
            status: 200, data: Data("replacement".utf8),
            headers: ["Content-Type": "image/png"]
        )
    }

    /// Wait until the first image is suspended, without sleeping.
    func waitForFirst() async {
        if suspended != nil { return }
        await withCheckedContinuation { continuation in waiting = continuation }
    }

    /// Release the original image even if its network task was canceled.
    func releaseOriginal() {
        suspended?.resume(returning: HTTPResult(
            status: 200, data: Data("obsolete".utf8),
            headers: ["Content-Type": "image/png"]
        ))
        suspended = nil
    }

    /// Count actual synthetic network requests.
    ///
    /// - Returns: Number of artwork downloads.
    func requestCount() -> Int { sends }
}

/// Clearing generation seven rejects an old in-flight response, not just NSCache.
@Test func publicationAdvanceRejectsLateArtworkAndCachesReplacement() async throws {
    let transport = DelayedArtworkTransport()
    let cache = ArtworkCache(transport: transport)
    let url = URL(string: "https://cdn2.unrealengine.com/fixture.png")!
    let original = Task { try await cache.load(url) }
    await transport.waitForFirst()
    await cache.clearForPublicationChange()
    let replacement = try await cache.load(url)
    await transport.releaseOriginal()

    await #expect(throws: CancellationError.self) {
        try await original.value
    }
    #expect(String(decoding: replacement.data, as: UTF8.self) == "replacement")
    #expect(!replacement.fromMemory)
    #expect((try await cache.load(url)).fromMemory)
    #expect(await transport.requestCount() == 2)
}
