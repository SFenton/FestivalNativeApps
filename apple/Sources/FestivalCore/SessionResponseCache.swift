import Foundation
import OSLog

/// A public-response cache scoped to the lifetime of this process.
public actor SessionResponseCache {
    private struct Key: Hashable {
        let resource: String
        let publicationId: Int
    }

    private struct ObservedKey: Hashable {
        let resource: String
        let observedPublicationId: Int
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

    /// Validated bytes last seen during a bootstrap, without response provenance.
    struct UnverifiedSnapshot: Sendable, Equatable {
        let data: Data
        let observedPublicationId: Int

        /// Retain bytes without pretending they were publication-bound.
        ///
        /// - Parameters:
        ///   - data: A typed, validated public endpoint's unmodified wire bytes.
        ///   - observedPublicationId: Bootstrap observed during the read, not byte provenance.
        init(data: Data, observedPublicationId: Int) {
            self.data = data
            self.observedPublicationId = observedPublicationId
        }
    }

    private static let log = Logger(
        subsystem: "com.sfenton.festivalscoretracker", category: "response-cache"
    )
    private var entries: [Key: Entry] = [:]
    private var unverified: [ObservedKey: UnverifiedSnapshot] = [:]
    private var recency: [ObservedKey] = []
    private var unverifiedBytes = 0
    private let unverifiedByteLimit: Int
    private let unverifiedEntryLimit: Int

    /// Creates an empty process-lifetime cache.
    public init() {
        unverifiedByteLimit = 16_000_000
        unverifiedEntryLimit = 128
    }

    /// Set small deterministic budgets for eviction and invalid-input tests.
    ///
    /// - Parameters:
    ///   - unverifiedByteLimit: Positive maximum total unpinned JSON bytes.
    ///   - unverifiedEntryLimit: Positive maximum separately keyed pages.
    /// - Throws: `FestivalAPIError.invalidResource` for nonpositive limits.
    init(unverifiedByteLimit: Int, unverifiedEntryLimit: Int) throws {
        guard unverifiedByteLimit > 0, unverifiedEntryLimit > 0 else {
            throw FestivalAPIError.invalidResource
        }
        self.unverifiedByteLimit = unverifiedByteLimit
        self.unverifiedEntryLimit = unverifiedEntryLimit
    }

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

    /// Reuse a last-seen response only during the same observed bootstrap.
    ///
    /// - Parameters:
    ///   - resource: Exact endpoint URL, including any paging/filter query.
    ///   - observedPublicationId: Bootstrap currently observed by the client.
    /// - Returns: An explicitly unverified snapshot, or nil when absent/evicted.
    func unverifiedSnapshot(
        for resource: String, observedPublicationId: Int
    ) -> UnverifiedSnapshot? {
        let key = ObservedKey(
            resource: resource, observedPublicationId: observedPublicationId
        )
        guard let snapshot = unverified[key] else { return nil }
        recency.removeAll { $0 == key }
        recency.append(key)
        return snapshot
    }

    /// Keep a validated headerless response under a separate, bounded LRU.
    ///
    /// - Parameters:
    ///   - snapshot: Unpinned bytes with only an observed bootstrap identifier.
    ///   - resource: Exact endpoint URL, not an operational or artwork request.
    /// - Returns: False only when a single response exceeds the process budget.
    @discardableResult
    func storeUnverified(
        _ snapshot: UnverifiedSnapshot, for resource: String
    ) -> Bool {
        let key = ObservedKey(
            resource: resource, observedPublicationId: snapshot.observedPublicationId
        )
        if let previous = unverified.removeValue(forKey: key) {
            unverifiedBytes -= previous.data.count
            recency.removeAll { $0 == key }
        }
        guard snapshot.data.count <= unverifiedByteLimit else {
            Self.log.warning("Unverified response exceeds in-process cache limit")
            return false
        }
        unverified[key] = snapshot
        unverifiedBytes += snapshot.data.count
        recency.append(key)
        while unverified.count > unverifiedEntryLimit
            || unverifiedBytes > unverifiedByteLimit {
            let oldest = recency.removeFirst()
            if let evicted = unverified.removeValue(forKey: oldest) {
                unverifiedBytes -= evicted.data.count
            }
        }
        return true
    }

    /// Discard an old-generation snapshot without clearing current-generation data.
    ///
    /// - Parameters:
    ///   - resource: Exact endpoint URL to remove.
    ///   - observedPublicationId: Bootstrap of the aborted snapshot.
    func removeUnverified(
        for resource: String, observedPublicationId: Int
    ) {
        let key = ObservedKey(
            resource: resource, observedPublicationId: observedPublicationId
        )
        if let removed = unverified.removeValue(forKey: key) {
            unverifiedBytes -= removed.data.count
            recency.removeAll { $0 == key }
        }
    }

    /// Discards all payloads when a different publication becomes current.
    public func removeAll() {
        entries.removeAll()
        unverified.removeAll()
        recency.removeAll()
        unverifiedBytes = 0
    }
}
