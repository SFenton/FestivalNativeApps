import Foundation

/// Artwork bytes with an explicit memory-origin indicator for presentation.
public struct ArtworkPayload: Sendable {
    public let data: Data
    public let fromMemory: Bool
}

/// Process-lifetime image cache that never persists album art across cold starts.
public actor ArtworkCache {
    private let transport: any HTTPTransport
    private let images = NSCache<NSURL, NSData>()
    private var inFlight: [URL: Task<Data, Error>] = [:]

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
        let download: Task<Data, Error>
        if let existing = inFlight[url] {
            download = existing
        } else {
            let transport = self.transport
            download = Task {
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
            inFlight[url] = download
        }
        do {
            let data = try await download.value
            images.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            inFlight[url] = nil
            try Task.checkCancellation()
            return ArtworkPayload(data: data, fromMemory: false)
        } catch {
            inFlight[url] = nil
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
