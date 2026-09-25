import Foundation

/// A public-response cache scoped to the lifetime of this process.
public actor SessionResponseCache {
    private struct Key: Hashable {
        let resource: String
        let publicationId: Int
    }

    /// A response tagged with the publication against which it was loaded.
    public struct Entry: Sendable, Equatable {
        public let data: Data
        public let publicationId: Int
        public let etag: String?

        /// Creates a publication-tagged in-memory response.
        ///
        /// - Parameters:
        ///   - data: Wire payload, without expanding or persisting it.
        ///   - publicationId: Published generation that produced the payload.
        ///   - etag: Optional server entity tag for safe revalidation.
        public init(data: Data, publicationId: Int, etag: String?) {
            self.data = data
            self.publicationId = publicationId
            self.etag = etag
        }
    }

    private var entries: [Key: Entry] = [:]

    /// Creates an empty process-lifetime cache.
    public init() {}

    /// Looks up a response only when it belongs to the current publication.
    ///
    /// - Parameters:
    ///   - resource: Stable endpoint identifier.
    ///   - publicationId: Currently published generation.
    /// - Returns: Cached response, or nil if missing/stale.
    public func entry(for resource: String, publicationId: Int) -> Entry? {
        entries[Key(resource: resource, publicationId: publicationId)]
    }

    /// Replaces a cached response for the given public endpoint.
    ///
    /// - Parameters:
    ///   - entry: Newly fetched public response.
    ///   - resource: Stable endpoint identifier.
    public func store(_ entry: Entry, for resource: String) {
        entries[Key(resource: resource, publicationId: entry.publicationId)] = entry
    }

    /// Discards all payloads when a different publication becomes current.
    public func removeAll() {
        entries.removeAll()
    }
}
