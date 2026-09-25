import Foundation

/// Artwork bytes with an explicit memory-origin indicator for presentation.
public struct ArtworkPayload: Sendable {
    public let data: Data
    public let fromMemory: Bool
}

/// Process-lifetime image cache that never persists album art across cold starts.
public actor ArtworkCache {
    private struct Download {
        let token: UUID
        let task: Task<Data, Error>
    }

    private let transport: any HTTPTransport
    private let images = NSCache<NSURL, NSData>()
    private var inFlight: [URL: Download] = [:]
    private var generation = 0

    /// Use the same ephemeral transport contract as the JSON client.
    ///
    /// - Parameters:
    ///   - transport: Injectable, disk-cache-free HTTP transport.
    ///   - memoryLimit: Maximum raw-artwork bytes retained within this process.
    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        memoryLimit: Int = 32_000_000
    ) {
        self.transport = transport
        images.totalCostLimit = max(1, memoryLimit)
    }

    /// Discard old art when the observed service publication advances.
    public func clearForPublicationChange() {
        generation += 1
        images.removeAllObjects()
        for download in inFlight.values {
            download.task.cancel()
        }
        inFlight.removeAll()
    }

    /// Reuse memory first, coalescing concurrent image requests to one download.
    ///
    /// - Parameter url: HTTPS CDN or loopback fixture image URL.
    /// - Returns: Validated image bytes and whether they came from memory.
    /// - Throws: Network, HTTP or artwork validation failures.
    public func load(_ url: URL) async throws -> ArtworkPayload {
        try Task.checkCancellation()
        if let cached = images.object(forKey: url as NSURL) {
            return ArtworkPayload(data: cached as Data, fromMemory: true)
        }
        let observedGeneration = generation
        let download: Download
        if let existing = inFlight[url] {
            download = existing
        } else {
            let transport = self.transport
            let task = Task {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                let response = try await transport.send(request)
                guard response.status == 200 else {
                    throw FestivalAPIError.httpStatus(response.status)
                }
                guard response.header("Content-Type")?.lowercased().hasPrefix("image/") == true,
                      !response.data.isEmpty,
                      response.data.count <= 8_000_000 else {
                    throw FestivalAPIError.invalidArtwork
                }
                return response.data
            }
            download = Download(token: UUID(), task: task)
            inFlight[url] = download
        }
        do {
            let data = try await download.task.value
            guard generation == observedGeneration else { throw CancellationError() }
            try Task.checkCancellation()
            images.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            if inFlight[url]?.token == download.token {
                inFlight[url] = nil
            }
            return ArtworkPayload(data: data, fromMemory: false)
        } catch {
            if inFlight[url]?.token == download.token {
                inFlight[url] = nil
            }
            throw error
        }
    }
}

extension FestivalAPI {
    /// Resolve service artwork while isolating original fixture images from CDN paths.
    ///
    /// - Parameter raw: Absolute image URL, CDN-relative asset, or local fixture route.
    /// - Returns: Validated image URL; nil only when the song has no artwork.
    /// - Throws: `FestivalAPIError.invalidResource` for unsupported URL schemes.
    public func artworkURL(_ raw: String?) throws -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        let cdn = URL(string: "https://cdn2.unrealengine.com/")!
        let url: URL?
        if raw.hasPrefix("/__fixture__/") {
            guard ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "") else {
                throw FestivalAPIError.invalidResource
            }
            url = URL(string: raw, relativeTo: baseURL)?.absoluteURL
        } else if raw.contains("://") {
            url = URL(string: raw)
        } else {
            guard !raw.hasPrefix("/"), !raw.contains("..") else {
                throw FestivalAPIError.invalidResource
            }
            url = cdn.appendingPathComponent(raw)
        }
        guard let url,
              url.scheme == "https"
              || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? ""))
        else {
            throw FestivalAPIError.invalidResource
        }
        return url
    }
}
