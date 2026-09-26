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

/// A canceled request cannot replace valid Shop or path-image cache bytes.
@Test func canceledPublicCacheWritesNeverPromoteOldResponses() async throws {
    let cache = SessionResponseCache()
    let entry = SessionResponseCache.Entry(
        data: Data("obsolete".utf8), publicationId: 7, etag: "\"old\""
    )
    let shopWrite = Task { () throws -> Void in
        withUnsafeCurrentTask { $0?.cancel() }
        try await cache.storeIfActive(entry, for: "shop")
    }
    await #expect(throws: CancellationError.self) { try await shopWrite.value }
    #expect(await cache.entry(for: "shop", publicationId: 7) == nil)
    let imageWrite = Task { () throws -> Void in
        withUnsafeCurrentTask { $0?.cancel() }
        try await cache.storePathImageIfActive(entry, for: "image")
    }
    await #expect(throws: CancellationError.self) { try await imageWrite.value }
    #expect(await cache.entry(for: "image", publicationId: 7) == nil)
    await cache.store(entry, for: "shop")
    await cache.removeVerifiedIfMatching(entry, for: "shop")
    #expect(await cache.entry(for: "shop", publicationId: 7) == nil)
    #expect(await cache.storePathImage(entry, for: "image"))
    await cache.removeVerifiedIfMatching(entry, for: "image")
    #expect(await cache.entry(for: "image", publicationId: 7) == nil)
}
