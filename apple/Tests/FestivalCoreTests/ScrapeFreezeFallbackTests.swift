import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

/// Issue #554: during a scrape the service answers band-scoped reads only from its
/// stored published responses, keyed per selected-profile headers the apps never
/// send, so a native read misses and gets a scrape-freeze 503. These tests pin the
/// client rule: a verified same-publication copy is served, everything else fails.

private let freezePublicationJSON = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
 "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

/// Locally authored best/worst wire (never captured production data).
private let extremesWire = """
{"bandType":"Band_Duets","teamKey":"fixture-a:fixture-b","comboId":null,"limit":5,
 "best":[{"songId":"fixture-best","rank":1,"totalEntries":40,"percentile":0.025,"score":250000}],
 "worst":[{"songId":"fixture-worst","rank":38,"totalEntries":40,"percentile":0.95,"score":90000}]}
"""

private let rankingWire = """
{"accountId":"fixture-player-1","displayName":"Fixture Player 1","instrument":"Solo_Guitar",
 "songsPlayed":40,"totalChartedSongs":40,"coverage":1.0,"rawSkillRating":0.0041,
 "adjustedSkillRating":0.0041,"adjustedSkillRank":3,"weightedRating":0.9,
 "weightedRank":4,"fcRate":0.975,"fcRateRank":2,"totalScore":123456789,
 "totalScoreRank":5,"maxScorePercent":0.998,"maxScorePercentRank":1,
 "avgAccuracy":97.5,"fullComboCount":39,"avgStars":5.9,"bestRank":1,"avgRank":3.2,
 "rawMaxScorePercent":0.998,"rawWeightedRating":0.9,"computedAt":"2026-09-27T00:00:00Z",
 "totalRankedAccounts":500}
"""

private func ok(_ wire: String, publication: String = "7") -> HTTPResult {
    HTTPResult(status: 200, data: Data(wire.utf8), headers: ["X-FST-Publication-Id": publication])
}

private func frozen(_ reason: String? = "scrape", publication: String? = nil) -> HTTPResult {
    var headers = ["Retry-After": "30"]
    if let reason { headers[ServiceFreezeReason.header] = reason }
    if let publication { headers["X-FST-Publication-Id"] = publication }
    return HTTPResult(status: 503, data: Data(), headers: headers)
}

private func extremes(_ client: FestivalAPI) async throws -> BandSongExtremesPayload {
    try await client.bandSongExtremes(bandType: .duets, teamKey: "fixture-a:fixture-b")
}

// MARK: - Served

@Test(arguments: ["scrape", "post-process", "publish", "publication-commit", "PUBLICATION-COMMIT-DEFERRED"])
func bandBestWorstSongsSurviveAScrapeFreezeAfterTheyLoaded(reason: String) async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: freezePublicationJSON),
        ok(extremesWire),
        frozen(reason, publication: "7"),
    ])
    let client = try FestivalAPI(transport: transport)
    let first = try await extremes(client)
    let during = try await extremes(client)

    #expect(during.response == first.response)
    #expect(during.response.best.map(\.songId) == ["fixture-best"])
    #expect(during.response.worst.map(\.songId) == ["fixture-worst"])
    #expect(during.publicationId == 7)
    #expect(during.observedPublicationId == 7)
    #expect(!during.isStale)
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { request in
        request.value(forHTTPHeaderField: "X-API-Key") == nil
            && request.allHTTPHeaderFields?.keys.contains {
                $0.lowercased().hasPrefix("x-fst-selected-")
            } != true
    })
}

@Test func everyCacheableBandSectionSurvivesAScrapeFreeze() async throws {
    let rowsWire = """
    {"bandType":"Band_Duets","teamKey":"fixture-a:fixture-b","comboId":null,"count":1,
     "entries":[{"songId":"fixture-best","rank":1,"totalEntries":40,"percentile":0.025,"score":250000}]}
    """
    let historyWire = """
    {"bandType":"Band_Duets","teamKey":"fixture-a:fixture-b","days":30,"history":[]}
    """
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: freezePublicationJSON),
        ok(rowsWire), frozen(),
        ok(historyWire), frozen(),
    ])
    let client = try FestivalAPI(transport: transport)
    let rows = try await client.bandSongRows(bandType: .duets, teamKey: "fixture-a:fixture-b")
    let rowsDuring = try await client.bandSongRows(bandType: .duets, teamKey: "fixture-a:fixture-b")
    #expect(rowsDuring.response == rows.response)
    let history = try await client.bandRankHistory(bandType: .duets, teamKey: "fixture-a:fixture-b")
    let historyDuring = try await client.bandRankHistory(bandType: .duets, teamKey: "fixture-a:fixture-b")
    #expect(historyDuring.response == history.response)
}

// MARK: - Still failing

@Test func aBandNeverLoadedStillShowsTheFreezeNotAnEmptyResult() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: freezePublicationJSON),
        frozen(),
    ]))
    await #expect(throws: FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30")) {
        try await extremes(client)
    }
}

@Test func anOutageOrNonLifecycleFreezeNeverServesRetainedBytes() async throws {
    let outage = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: freezePublicationJSON),
        ok(extremesWire),
        frozen(nil),
    ]))
    _ = try await extremes(outage)
    await #expect(throws: FestivalAPIError.unavailable(retryAfter: "30")) {
        try await extremes(outage)
    }

    let isolation = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: freezePublicationJSON),
        ok(extremesWire),
        frozen("publication-isolation-pending"),
    ]))
    _ = try await extremes(isolation)
    await #expect(throws: FestivalAPIError.publicReadFrozen(
        reason: "publication-isolation-pending", retryAfter: "30"
    )) {
        try await extremes(isolation)
    }
}

@Test func aFreezeNamingAnotherPublicationNeverServesRetainedBytes() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: freezePublicationJSON),
        ok(extremesWire),
        frozen(publication: "8"),
    ]))
    _ = try await extremes(client)
    await #expect(throws: FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30")) {
        try await extremes(client)
    }
}

@Test func accountScopedReadsStayOutOfTheFreezeFallback() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: freezePublicationJSON),
        ok(rankingWire),
        frozen(),
    ]))
    _ = try await client.playerInstrumentRanking(instrument: .lead, accountId: "fixture-player-1")
    await #expect(throws: FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30")) {
        try await client.playerInstrumentRanking(instrument: .lead, accountId: "fixture-player-1")
    }
}

@Test func fallbackRuleIsPureAndScopedToTheAttemptPublication() {
    let entry = SessionResponseCache.Entry(data: Data("kept".utf8), publicationId: 7, etag: nil)
    #expect(FestivalAPI.scrapeFreezeFallback(frozen(), cached: entry, publicationId: 7) == Data("kept".utf8))
    #expect(FestivalAPI.scrapeFreezeFallback(frozen(), cached: entry, publicationId: 8) == nil)
    #expect(FestivalAPI.scrapeFreezeFallback(frozen(), cached: nil, publicationId: 7) == nil)
    #expect(FestivalAPI.scrapeFreezeFallback(
        frozen(publication: "not-a-number"), cached: entry, publicationId: 7
    ) == nil)
    #expect(FestivalAPI.scrapeFreezeFallback(ok("{}"), cached: entry, publicationId: 7) == nil)
    #expect(FestivalAPI.scrapeFreezeFallback(frozen(""), cached: entry, publicationId: 7) == nil)
}
