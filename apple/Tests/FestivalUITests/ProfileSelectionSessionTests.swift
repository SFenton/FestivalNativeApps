import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

actor ProfileSelectionTransport: HTTPTransport {
    private var generation = 7
    private var denied = false
    private var syncNext = false
    private var holdNext = false
    private var shouldOmitNextProfileHeader = false
    private var held: CheckedContinuation<HTTPResult, Error>?
    private var heldAccount: String?
    private var heldGeneration = 7
    private var waiting: CheckedContinuation<Void, Never>?
    private let unpinned: Bool

    /// Keep headerless fixture publication behavior independent of pinned tests.
    ///
    /// - Parameter unpinned: Omit response and request generation pins.
    init(unpinned: Bool = false) {
        self.unpinned = unpinned
    }

    /// Serve only synthetic publication and profile reads with no selected headers.
    ///
    /// - Parameter request: One public GET from the native session.
    /// - Returns: Generation-consistent fixture profile or explicit HTTP 403.
    /// - Throws: Any unsafe request or an intentionally held response.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        if request.url?.path == "/api/publication" {
            let pinning = !unpinned
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":\(generation),
             "publishedScrapeId":\(generation),"readyForPinning":\(pinning),
             "pinningEnabled":\(pinning),"unreadySurfaces":[]}
            """.utf8))
        }
        guard let accountId = request.url?.path.split(separator: "/").last.map(String.init),
              request.url?.path == "/api/player/\(accountId)",
              ["fixture-player-1", "fixture-player-2"].contains(accountId),
              (unpinned
                  ? request.value(forHTTPHeaderField: "X-FST-Publication-Id") == nil
                  : request.value(forHTTPHeaderField: "X-FST-Publication-Id")
                      == String(generation)) else {
            throw FestivalAPIError.invalidResource
        }
        if denied {
            return HTTPResult(status: 403, data: Data())
        }
        if syncNext {
            syncNext = false
            return HTTPResult(status: 202, data: Data("""
            {"accountId":"\(accountId)","displayName":"Syncing Player",
             "status":"syncing","notYetPublished":true,"totalScores":0,"scores":[]}
            """.utf8), headers: responseHeaders(for: generation))
        }
        if holdNext {
            holdNext = false
            heldAccount = accountId
            heldGeneration = generation
            return try await withCheckedThrowingContinuation { continuation in
                held = continuation
                waiting?.resume()
                waiting = nil
            }
        }
        let omitHeader = shouldOmitNextProfileHeader
        shouldOmitNextProfileHeader = false
        return profile(for: accountId, generation: generation, omitHeader: omitHeader)
    }

    /// Return one coherent score for the selected synthetic account.
    ///
    /// - Parameters:
    ///   - accountId: Fixture account one or two.
    ///   - generation: Response-proven publication to return.
    ///   - omitHeader: Simulate a keyless per-account read with no trusted
    ///     `X-FST-Publication-Id` response header, independent of the transport's
    ///     `unpinned` mode (e.g. edge pinning not yet enabled for this one read).
    /// - Returns: Current-state compact profile without a tracking write.
    private func profile(
        for accountId: String, generation: Int, omitHeader: Bool = false
    ) -> HTTPResult {
        let rank = accountId == "fixture-player-1" ? 1 : 2
        let body = """
        {"accountId":"\(accountId)","displayName":"Fixture Player \(rank)",
         "totalScores":1,"scores":[{"si":"fixture-pulse","ins":"01",
         "sc":\(100_000 - rank * 100),"acc":979,"fc":\(rank == 2),
         "st":5,"sn":9,"pct":\(Double(rank) / 26),"rk":\(rank),"te":26}]}
        """
        return HTTPResult(
            status: 200, data: Data(body.utf8),
            headers: omitHeader ? [:] : responseHeaders(for: generation)
        )
    }

    /// Match the fixture publication policy without adding selected-account headers.
    ///
    /// - Parameter generation: Request-consistent source publication.
    /// - Returns: Pinned generation header or an explicitly unpinned response.
    private func responseHeaders(for generation: Int) -> [String: String] {
        unpinned ? [:] : ["X-FST-Publication-Id": String(generation)]
    }

    /// Make a selected-profile refresh fail with a genuine status, not an empty result.
    ///
    /// - Parameter value: Whether subsequent profile GETs return HTTP 403.
    func setDenied(_ value: Bool) { denied = value }

    /// Return one 202 after a previously available selected-player read.
    func syncNextProfile() { syncNext = true }

    /// Make the next `/api/player/...` response omit its response publication
    /// header while the transport otherwise stays pinned, e.g. a keyless read
    /// the edge has not yet stamped even though `/api/publication` is pinned.
    func omitNextProfileHeader() { shouldOmitNextProfileHeader = true }

    /// Advance the fixture generation without changing a selected identity.
    ///
    /// - Parameter value: New publication ID to serve on bootstrap and profile reads.
    func setGeneration(_ value: Int) { generation = value }

    /// Hold the next account GET while another account is explicitly selected.
    func holdNextProfile() { holdNext = true }

    /// Observe that an actual request was suspended before switching accounts.
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }

    /// Deliver a previously held score after another account became selected.
    func releaseHeld() {
        guard let account = heldAccount else { return }
        held?.resume(returning: profile(for: account, generation: heldGeneration))
        held = nil
        heldAccount = nil
    }
}

/// Create one public search result without posting or visiting production.
///
/// - Parameter rank: Synthetic account one or two.
/// - Returns: Validated player result that is still merely viewed.
/// - Throws: Invalid locally authored JSON.
private func viewedPlayer(_ rank: Int) throws -> PlayerSearchResult {
    try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-\(rank)","displayName":"Fixture Player \(rank)"}
    """.utf8))
}

@MainActor
@Test func viewedPlayerRequiresSelectionAndRestoresOnlyIdentityOnRelaunch() async throws {
    let suiteName = "fst-profile-tests-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    let transport = ProfileSelectionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client }, selectionStorage: storage)

    let result = try viewedPlayer(1)
    let viewed = try await session.viewPlayer(result)
    #expect(session.selectedPlayer == nil)
    #expect(session.selectedPlayerScores.isEmpty)
    #expect(session.selectedPlayerScoreObservation == nil)
    try session.selectPlayer(result, from: viewed)
    #expect(session.playerLoadState == .available)
    #expect(session.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_900)
    #expect(session.selectedPlayerScoreObservation == 7)
    #expect(session.hasCurrentPlayerScores(forCatalogue: 7))
    #expect(!session.hasCurrentPlayerScores(forCatalogue: nil))
    let data = try #require(storage.data(forKey: SelectedPlayerIdentity.storageKey))
    #expect(try JSONDecoder().decode(SelectedPlayerIdentity.self, from: data).accountId
        == result.accountId)

    let restored = FestivalSession(factory: { client }, selectionStorage: storage)
    #expect(restored.selectedPlayer?.accountId == result.accountId)
    #expect(restored.playerLoadState == .loading)
    #expect(restored.selectedPlayerScores.isEmpty)
    #expect(restored.selectedPlayerScoreObservation == nil)
    await restored.refreshSelectedPlayer()
    #expect(restored.playerLoadState == .available)
    #expect(restored.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_900)
    #expect(restored.selectedPlayerScoreObservation == 7)
    storage.set(try SongPlayerScoreFilter(hasScores: [.lead]).encoded(),
                forKey: SongPlayerScoreFilter.storageKey)
    let general = try SongGeneralFilter(excludedDecades: [1970], doubleBassSupported: false).encoded()
    storage.set(general, forKey: SongGeneralFilter.storageKey)
    restored.deselectPlayer()
    #expect(restored.selectedPlayer == nil)
    #expect(restored.selectedPlayerScores.isEmpty)
    #expect(restored.selectedPlayerScoreObservation == nil)
    #expect(storage.data(forKey: SelectedPlayerIdentity.storageKey) == nil)
    #expect(storage.data(forKey: SongPlayerScoreFilter.storageKey) == nil)
    // General filters use only public metadata and survive deselection.
    #expect(storage.data(forKey: SongGeneralFilter.storageKey) == general)
}

@MainActor
@Test func corruptStoredIdentityIsVisibleAndCannotBecomeASelectedProfile() throws {
    let suiteName = "fst-profile-tests-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(Data("""
    {"accountId":"../other","displayName":"Untrusted"}
    """.utf8), forKey: SelectedPlayerIdentity.storageKey)
    let session = FestivalSession(
        factory: { throw FestivalAPIError.invalidResource },
        selectionStorage: storage
    )
    #expect(session.selectedPlayer == nil)
    #expect(session.playerError == FestivalAPIError.invalidSelectedProfile.localizedDescription)
    #expect(storage.data(forKey: SelectedPlayerIdentity.storageKey) == nil)
}

@MainActor
@Test func failedAndChangedPublicationClearSelectedScoresWithoutErasingIdentity() async throws {
    let transport = ProfileSelectionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let result = try viewedPlayer(1)
    try session.selectPlayer(result, from: await session.viewPlayer(result))
    await transport.setDenied(true)
    await session.refreshSelectedPlayer()
    #expect(session.selectedPlayer?.accountId == result.accountId)
    #expect(session.selectedPlayerScores.isEmpty)
    #expect(session.selectedPlayerScoreObservation == nil)
    guard case .failed = session.playerLoadState else {
        Issue.record("HTTP 403 must remain a visible failure, not an anonymous score")
        return
    }
    await transport.setDenied(false)
    await session.refreshSelectedPlayer()
    #expect(session.playerLoadState == .available)
    #expect(session.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_900)
    #expect(session.selectedPlayerScoreObservation == 7)

    await transport.setGeneration(8)
    _ = try await session.refreshPublication()
    #expect(session.publicationRevision == 1)
    #expect(session.selectedPlayer?.accountId == result.accountId)
    #expect(session.selectedPlayerScores.isEmpty)
    #expect(session.selectedPlayerScoreObservation == nil)
    #expect(session.playerLoadState == .loading)
    await session.refreshSelectedPlayer()
    #expect(session.playerLoadState == .available)
    #expect(session.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_900)
    #expect(session.selectedPlayerScoreObservation == 8)
    #expect(!session.hasCurrentPlayerScores(forCatalogue: 7))
    #expect(session.hasCurrentPlayerScores(forCatalogue: 8))
}

/// A selected 202 keeps identity while a user-initiated retry may restore scores.
@MainActor
@Test func selectedProfileSyncingCanBeRetriedWithoutStaleScoreDisplay() async throws {
    let transport = ProfileSelectionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let player = try viewedPlayer(1)
    try session.selectPlayer(player, from: await session.viewPlayer(player))
    await transport.syncNextProfile()
    await session.refreshSelectedPlayer()
    #expect(session.selectedPlayer?.accountId == player.accountId)
    #expect(session.playerLoadState == .syncing)
    #expect(session.selectedPlayerScores.isEmpty)
    #expect(session.selectedPlayerScoreObservation == nil)
    #expect(session.playerError == nil)
    await session.refreshSelectedPlayer()
    #expect(session.playerLoadState == .available)
    #expect(session.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_900)
    #expect(session.selectedPlayerScoreObservation == 7)
}

/// A headerless player response may be viewed but cannot persist selected identity.
@MainActor
@Test func unpinnedPlayerReadCannotBecomeSelectedOrPersist() async throws {
    let suiteName = "fst-profile-tests-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    let transport = ProfileSelectionTransport(unpinned: true)
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    let player = try viewedPlayer(1)
    let preview = try await session.viewPlayer(player)
    #expect(preview.publicationId == nil)
    #expect(preview.observedPublicationId == 7)
    #expect(throws: FestivalAPIError.invalidPublication) {
        try session.selectPlayer(player, from: preview)
    }
    #expect(session.selectedPlayer == nil)
    #expect(session.selectedPlayerScores.isEmpty)
    #expect(session.selectedPlayerScoreObservation == nil)
    #expect(storage.data(forKey: SelectedPlayerIdentity.storageKey) == nil)
}

/// A preview from an old generation cannot select a player after publication changes.
@MainActor
@Test func staleViewedPlayerNeedsAnUpdatedPublishedPreviewBeforeSelection() async throws {
    let transport = ProfileSelectionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let player = try viewedPlayer(1)
    let oldPreview = try await session.viewPlayer(player)
    await transport.setGeneration(8)
    _ = try await session.refreshPublication()
    #expect(session.publicationRevision == 1)
    #expect(throws: FestivalAPIError.invalidPublication) {
        try session.selectPlayer(player, from: oldPreview)
    }
    let updated = try await session.viewPlayer(player)
    #expect(updated.publicationId == 8)
    try session.selectPlayer(player, from: updated)
    #expect(session.selectedPlayer?.accountId == player.accountId)
    #expect(session.selectedPlayerScoreObservation == 8)
}

@MainActor
@Test func latePreviousPlayerReadCannotOverwriteExplicitlySwitchedScores() async throws {
    let transport = ProfileSelectionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let first = try viewedPlayer(1)
    try session.selectPlayer(first, from: await session.viewPlayer(first))
    await transport.holdNextProfile()
    let pending = Task { await session.refreshSelectedPlayer() }
    await transport.waitUntilHeld()

    let second = try viewedPlayer(2)
    try session.selectPlayer(second, from: await session.viewPlayer(second))
    #expect(session.selectedPlayer?.accountId == second.accountId)
    #expect(session.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_800)
    #expect(session.selectedPlayerScoreObservation == 7)
    await transport.releaseHeld()
    await pending.value
    #expect(session.selectedPlayer?.accountId == second.accountId)
    #expect(session.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_800)
    #expect(session.selectedPlayerScoreObservation == 7)
    #expect(session.playerError == nil)
}

/// Regression: a relaunch reload of an already-selected, already-persisted identity
/// must not fail just because that one response lacked a trusted publication header.
/// `refreshSelectedPlayer` previously compared `payload.publicationId` against
/// `self.publicationId`, but the latter had already been advanced to
/// `payload.observedPublicationId` by the same call, making the guard equivalent to
/// `payload.publicationId == payload.observedPublicationId` — always false for a
/// headerless response, so cold-start restoration could never actually recover a
/// previously selected player's scores.
@MainActor
@Test func relaunchReloadSurvivesAHeaderlessButOtherwiseCurrentProfileRead() async throws {
    let suiteName = "fst-profile-tests-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    let transport = ProfileSelectionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    let player = try viewedPlayer(1)
    try session.selectPlayer(player, from: await session.viewPlayer(player))

    let restored = FestivalSession(factory: { client }, selectionStorage: storage)
    #expect(restored.selectedPlayer?.accountId == player.accountId)
    #expect(restored.playerLoadState == .loading)
    await transport.omitNextProfileHeader()
    await restored.refreshSelectedPlayer()
    #expect(restored.selectedPlayer?.accountId == player.accountId)
    #expect(restored.playerLoadState == .available)
    #expect(restored.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_900)
    #expect(restored.selectedPlayerScoreObservation == 7)
    #expect(restored.playerError == nil)
}
