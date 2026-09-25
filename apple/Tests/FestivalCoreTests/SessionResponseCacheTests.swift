import Foundation
import Testing
@testable import FestivalCore

/// Headerless memory must stay separate from response-proven generation and ETag data.
@Test func unverifiedSnapshotsStayBoundedAndSeparateFromVerifiedEntries() async throws {
    let cache = try SessionResponseCache(unverifiedByteLimit: 6, unverifiedEntryLimit: 2)
    let verified = SessionResponseCache.Entry(
        data: Data("bound".utf8), publicationId: 7, etag: "verified-etag"
    )
    await cache.store(verified, for: "songs")
    #expect(await cache.storeUnverified(
        .init(data: Data("aaa".utf8), observedPublicationId: 7), for: "first"
    ))
    #expect(await cache.storeUnverified(
        .init(data: Data("bb".utf8), observedPublicationId: 7), for: "second"
    ))
    _ = await cache.unverifiedSnapshot(for: "first", observedPublicationId: 7)
    #expect(await cache.storeUnverified(
        .init(data: Data("cc".utf8), observedPublicationId: 7), for: "third"
    ))
    #expect(await cache.unverifiedSnapshot(for: "second", observedPublicationId: 7) == nil)
    #expect(await cache.unverifiedSnapshot(for: "first", observedPublicationId: 7)?.data
            == Data("aaa".utf8))
    #expect(await cache.entry(for: "songs", publicationId: 7) == verified)
    #expect(await cache.unverifiedSnapshot(for: "first", observedPublicationId: 8) == nil)

    #expect(!(await cache.storeUnverified(
        .init(data: Data("too large".utf8), observedPublicationId: 7), for: "first"
    )))
    #expect(await cache.unverifiedSnapshot(for: "first", observedPublicationId: 7) == nil)
    #expect(await cache.unverifiedSnapshot(for: "third", observedPublicationId: 7) != nil)
    await cache.removeUnverified(for: "third", observedPublicationId: 7)
    #expect(await cache.unverifiedSnapshot(for: "third", observedPublicationId: 7) == nil)
    #expect(await cache.storeUnverified(
        .init(data: Data("new".utf8), observedPublicationId: 7), for: "latest"
    ))
    await cache.removeAll()
    #expect(await cache.entry(for: "songs", publicationId: 7) == nil)
    #expect(await cache.unverifiedSnapshot(for: "latest", observedPublicationId: 7) == nil)
}

/// Byte budgets and a true cold launch cannot silently retain prior-session data.
@Test func unverifiedSnapshotBudgetsAndProcessLifetimeAreExplicit() async throws {
    #expect(throws: FestivalAPIError.invalidResource) {
        try SessionResponseCache(unverifiedByteLimit: 0, unverifiedEntryLimit: 2)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try SessionResponseCache(unverifiedByteLimit: 8, unverifiedEntryLimit: 0)
    }
    let warm = try SessionResponseCache(unverifiedByteLimit: 5, unverifiedEntryLimit: 3)
    #expect(await warm.storeUnverified(
        .init(data: Data("aaaa".utf8), observedPublicationId: 7), for: "one"
    ))
    #expect(await warm.storeUnverified(
        .init(data: Data("bb".utf8), observedPublicationId: 7), for: "two"
    ))
    #expect(await warm.unverifiedSnapshot(for: "one", observedPublicationId: 7) == nil)
    #expect(await warm.unverifiedSnapshot(for: "two", observedPublicationId: 7) != nil)
    let cold = SessionResponseCache()
    #expect(await cold.unverifiedSnapshot(for: "two", observedPublicationId: 7) == nil)
}
