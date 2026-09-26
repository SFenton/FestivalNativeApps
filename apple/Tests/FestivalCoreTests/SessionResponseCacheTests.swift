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

/// Large publication-proven PNGs must not crowd out Songs or grow without a bound.
@Test func songPathVerifiedImagesUseSeparateBoundedMemory() async throws {
    #expect(throws: FestivalAPIError.invalidResource) {
        try SessionResponseCache(
            unverifiedByteLimit: 8, unverifiedEntryLimit: 2,
            pathImageByteLimit: 0
        )
    }
    let cache = try SessionResponseCache(
        unverifiedByteLimit: 8, unverifiedEntryLimit: 2,
        pathImageByteLimit: 5, pathImageEntryLimit: 2
    )
    let songs = SessionResponseCache.Entry(
        data: Data("songs".utf8), publicationId: 7, etag: nil
    )
    await cache.store(songs, for: "catalog")
    let first = SessionResponseCache.Entry(
        data: Data("aaa".utf8), publicationId: 7, etag: "first"
    )
    let second = SessionResponseCache.Entry(
        data: Data("bb".utf8), publicationId: 7, etag: "second"
    )
    let third = SessionResponseCache.Entry(
        data: Data("cc".utf8), publicationId: 7, etag: "third"
    )
    #expect(await cache.storePathImage(first, for: "path-a"))
    #expect(await cache.storePathImage(second, for: "path-b"))
    _ = await cache.entry(for: "path-a", publicationId: 7)
    #expect(await cache.storePathImage(third, for: "path-c"))
    #expect(await cache.entry(for: "path-b", publicationId: 7) == nil)
    #expect(await cache.entry(for: "path-a", publicationId: 7) == first)
    #expect(await cache.entry(for: "path-c", publicationId: 7) == third)
    #expect(await cache.entry(for: "catalog", publicationId: 7) == songs)
    let oversized = SessionResponseCache.Entry(
        data: Data("too large".utf8), publicationId: 7, etag: nil
    )
    #expect(!(await cache.storePathImage(oversized, for: "path-a")))
    #expect(await cache.entry(for: "path-a", publicationId: 7) == nil)
    await cache.removeAll()
    #expect(await cache.entry(for: "path-c", publicationId: 7) == nil)
    #expect(await cache.entry(for: "catalog", publicationId: 7) == nil)
}
