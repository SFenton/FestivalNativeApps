#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixture transport

/// Minimal keyless fixture transport for the Leaderboards feature's hosted renders:
/// publication plus `/api/rankings/*`, matching the service-safety rules enforced by
/// every other fixture transport in this target (no `X-API-Key`, no selected-profile
/// headers, publication-pinned reads).
actor HostedRankingsTransport: HTTPTransport {
    private let generation = 11
    /// When true, every rankings/band-rankings request returns zero entries
    /// (the "no ranked players yet" empty state).
    var empty = false
    /// Single-account spotlight fixture, keyed by `"<instrument>:<accountId>"`.
    /// Absent keys 404 (the honest "not ranked yet" state).
    var spotlightRanks: [String: Int] = [:]
    /// When true, every single-account spotlight request fails.
    var spotlightFails = false
    /// Artificial delay before answering a single-account spotlight request, to
    /// deterministically capture its loading state in a hosted screenshot.
    var spotlightDelayMs: UInt64 = 0
    /// Count of single-account spotlight reads actually sent, to prove the
    /// screen skips the read entirely when the row is already visible.
    private(set) var spotlightCalls = 0

    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        if url.path == "/api/publication" {
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":\(generation),"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        guard request.value(forHTTPHeaderField: "X-FST-Publication-Id")
                == String(generation) else {
            throw FestivalAPIError.invalidPublication
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { a, _ in a }
        )
        let page = Int(query["page"] ?? "1") ?? 1
        let rankBy = query["rankBy"] ?? "totalscore"
        if url.pathComponents.count == 5, url.pathComponents[1] == "api",
           url.pathComponents[2] == "rankings", url.pathComponents[3] == "bands" {
            let bandType = url.pathComponents[4]
            return HTTPResult(
                status: 200,
                data: try bandRankingsBody(bandType: bandType, rankBy: rankBy, page: page),
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        if url.pathComponents.count == 5, url.pathComponents[1] == "api",
           url.pathComponents[2] == "rankings" {
            let instrument = url.pathComponents[3]
            let accountId = url.pathComponents[4]
            spotlightCalls += 1
            if spotlightDelayMs > 0 {
                try await Task.sleep(nanoseconds: spotlightDelayMs * 1_000_000)
            }
            if spotlightFails {
                throw FestivalAPIError.httpStatus(500)
            }
            guard let rank = spotlightRanks["\(instrument):\(accountId)"] else {
                throw FestivalAPIError.httpStatus(404)
            }
            return HTTPResult(
                status: 200,
                data: try singleAccountRankingBody(
                    instrument: instrument, accountId: accountId, rank: rank
                ),
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        if url.pathComponents.count == 4, url.pathComponents[1] == "api",
           url.pathComponents[2] == "rankings" {
            let instrument = url.pathComponents[3]
            return HTTPResult(
                status: 200,
                data: try rankingsBody(instrument: instrument, rankBy: rankBy, page: page),
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        throw FestivalAPIError.httpStatus(404)
    }

    /// Toggle whether subsequent requests describe an empty board.
    ///
    /// - Parameter value: True to serve zero entries for every instrument/band.
    func setEmpty(_ value: Bool) {
        empty = value
    }

    /// Register a fixture rank for one account's single-account spotlight read.
    ///
    /// - Parameters:
    ///   - instrument: Requested chart.
    ///   - accountId: Requested account.
    ///   - rank: Rank to serve for every metric (kept equal for simplicity).
    func setSpotlightRank(instrument: String, accountId: String, rank: Int) {
        spotlightRanks["\(instrument):\(accountId)"] = rank
    }

    /// Force every subsequent single-account spotlight read to fail.
    ///
    /// - Parameter value: True to throw a 500 for the spotlight endpoint.
    func setSpotlightFails(_ value: Bool) {
        spotlightFails = value
    }

    /// Delay every subsequent single-account spotlight read.
    ///
    /// - Parameter milliseconds: Artificial delay before responding.
    func setSpotlightDelay(_ milliseconds: UInt64) {
        spotlightDelayMs = milliseconds
    }

    private func singleAccountRankingBody(instrument: String, accountId: String, rank: Int) throws -> Data {
        let body: [String: Any] = [
            "accountId": accountId, "displayName": "Spotlight Player",
            "instrument": instrument, "totalRankedAccounts": 500,
            "songsPlayed": 30, "totalChartedSongs": 50, "coverage": 0.6,
            "rawSkillRating": 0.02, "adjustedSkillRating": 0.02, "adjustedSkillRank": rank,
            "weightedRating": 0.03, "weightedRank": rank, "fcRate": 0.5, "fcRateRank": rank,
            "totalScore": 40_000_000, "totalScoreRank": rank,
            "maxScorePercent": 0.9, "maxScorePercentRank": rank, "avgAccuracy": 0.9,
            "fullComboCount": 10, "avgStars": 4.2, "bestRank": rank, "avgRank": Double(rank),
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func rankingsBody(instrument: String, rankBy: String, page: Int) throws -> Data {
        let entries: [[String: Any]] = empty ? [] : (1...3).map { rank in
            [
                "accountId": "fixture-rank-\(rank)", "displayName": "Fixture Rank \(rank)",
                "songsPlayed": 40, "totalChartedSongs": 50, "coverage": 0.8,
                "rawSkillRating": 0.02, "adjustedSkillRating": 0.02, "adjustedSkillRank": rank,
                "weightedRating": 0.03, "weightedRank": rank, "fcRate": 0.5, "fcRateRank": rank,
                "totalScore": 90_000_000 - rank * 1000, "totalScoreRank": rank,
                "maxScorePercent": 0.97, "maxScorePercentRank": rank, "avgAccuracy": 0.98,
                "fullComboCount": 20, "avgStars": 4.8, "bestRank": 1, "avgRank": 2.5,
            ]
        }
        let body: [String: Any] = [
            "instrument": instrument, "rankBy": rankBy, "page": page, "pageSize": 10,
            "totalAccounts": entries.count, "entries": entries,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func bandRankingsBody(bandType: String, rankBy: String, page: Int) throws -> Data {
        let entries: [[String: Any]] = empty ? [] : (1...2).map { rank in
            [
                "bandId": "fixture-band-\(rank)", "teamKey": "team-\(rank)",
                "teamMembers": [
                    ["accountId": "fixture-member-\(rank)a", "displayName": "Member \(rank)A"],
                    ["accountId": "fixture-member-\(rank)b", "displayName": "Member \(rank)B"],
                ],
                "songsPlayed": 30, "totalChartedSongs": 50, "coverage": 0.6,
                "rawSkillRating": 0.02, "adjustedSkillRating": 0.02, "adjustedSkillRank": rank,
                "weightedRating": 0.03, "weightedRank": rank, "fcRate": 0.4, "fcRateRank": rank,
                "totalScore": 50_000_000 - rank * 1000, "totalScoreRank": rank,
                "avgAccuracy": 0.95, "fullComboCount": 10, "avgStars": 4.5, "bestRank": 1,
                "avgRank": 3.1,
            ]
        }
        let body: [String: Any] = [
            "bandType": bandType, "rankBy": rankBy, "page": page, "pageSize": 10,
            "totalTeams": entries.count, "entries": entries,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }
}

/// Build a fixture-backed session (no selected profile needed; rankings are public).
@MainActor
private func hostedRankingsSession(transport: HostedRankingsTransport) -> FestivalSession {
    let client = try! FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    return FestivalSession(factory: { client })
}

/// Build a fixture-backed session with a player already selected in memory
/// (`debugSelectedPlayer`), for the selected-player spotlight hosted renders —
/// never touches real `UserDefaults`.
///
/// - Parameters:
///   - transport: Shared rankings fixture transport.
///   - accountId: Selected player's fixture account id.
///   - displayName: Selected player's fixture display name.
/// - Returns: A session that already reports this player selected.
@MainActor
private func hostedRankingsSessionWithSelection(
    transport: HostedRankingsTransport, accountId: String, displayName: String
) throws -> FestivalSession {
    let client = try! FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"\(accountId)","displayName":"\(displayName)"}
    """.utf8))
    return FestivalSession(
        factory: { client },
        debugSelectedPlayer: try SelectedPlayerIdentity(searchResult: result)
    )
}

// MARK: - Hosted storage

private extension View {
    /// Render with the app's Reduce Motion on: load-in fades never advance in an
    /// offscreen host, so rows would otherwise stay transparent.
    ///
    /// - Returns: The view reading a test-only defaults suite.
    func leaderboardsHostedStorage() -> some View {
        let defaults = UserDefaults(suiteName: "fst.tests.leaderboards.host")!
        defaults.set(true, forKey: "fst.accessibility.reduceMotion")
        return defaultAppStorage(defaults)
    }
}

// MARK: - LeaderboardsScreen overview

/// Every visible instrument and band card loads and renders its top rows.
@MainActor
@Test func leaderboardsScreenRendersInstrumentAndBandCards() async throws {
    let transport = HostedRankingsTransport()
    let session = hostedRankingsSession(transport: transport)
    let size = CGSize(width: 402, height: 1200)
    let host = nativeHostedView(
        LeaderboardsScreen(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture Rank 1", "Fixture Rank 3", "View all rankings (3)"], timeout: .seconds(60)
    )
    _ = try nativeHostedPNG(image, filename: "leaderboards-overview.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Fixture Rank 1", "Fixture Rank 3", "View all rankings (3)"])
}

/// The "no ranked players yet" / "no ranked … yet" empty-card text for every card.
@MainActor
@Test func leaderboardsScreenRendersEmptyCards() async throws {
    let transport = HostedRankingsTransport()
    await transport.setEmpty(true)
    let session = hostedRankingsSession(transport: transport)
    let size = CGSize(width: 402, height: 1200)
    let host = nativeHostedView(
        LeaderboardsScreen(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["No ranked Lead players yet."], timeout: .seconds(60))
    _ = try nativeHostedPNG(image, filename: "leaderboards-empty.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["No ranked Lead players yet."], notContaining: ["Fixture Rank 1"]
    )
}

// MARK: - FullRankingsScreen

/// The paginated full-rankings board renders its rows for the requested instrument.
@MainActor
@Test func fullRankingsScreenRendersRows() async throws {
    let transport = HostedRankingsTransport()
    let session = hostedRankingsSession(transport: transport)
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(
        FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore")
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Fixture Rank 1", "Fixture Rank 3", "First page", "Lead Rankings"], timeout: .seconds(60))
    _ = try nativeHostedPNG(image, filename: "full-rankings.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Fixture Rank 1", "Fixture Rank 3", "First page", "Lead Rankings"])
}

// MARK: - BandRankingsScreen

/// The paginated band-rankings board renders its rows for the requested band size.
@MainActor
@Test func bandRankingsScreenRendersRows() async throws {
    let transport = HostedRankingsTransport()
    let session = hostedRankingsSession(transport: transport)
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(
        BandRankingsScreen(session: session, bandType: "Band_Duets")
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Member 1A", "Member 2B", "First Page", "Duos"], timeout: .seconds(60))
    _ = try nativeHostedPNG(image, filename: "band-rankings.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Member 1A", "Member 2B", "First Page", "Duos"])
}

// MARK: - LeaderboardsScreen selected-player spotlight

/// The selected player's row is highlighted in place when already in the top ten.
@MainActor
@Test func leaderboardsScreenHighlightsSelectedRowWhenInTopTen() async throws {
    let transport = HostedRankingsTransport()
    // The fixture top-ten rows are "fixture-rank-1"/"2"/"3"; selecting one of
    // them must highlight it inline rather than adding a spotlight footer.
    let session = try hostedRankingsSessionWithSelection(
        transport: transport, accountId: "fixture-rank-2", displayName: "Fixture Rank 2"
    )
    let size = CGSize(width: 402, height: 1200)
    let host = nativeHostedView(
        LeaderboardsScreen(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Your rank, 2nd. Fixture Rank 2."], timeout: .seconds(60))
    _ = try nativeHostedPNG(
        image, filename: "leaderboards-spotlight-inline.png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image,
        containing: ["Your rank, 2nd. Fixture Rank 2."],
        notContaining: ["Loading your rank"]
    )
    // No live single-account read was needed since the row was already visible.
    #expect(await transport.spotlightCalls == 0)
}

/// A selected player ranked below the top ten shows a separate spotlight row.
@MainActor
@Test func leaderboardsScreenShowsSpotlightFooterWhenBelowTopTen() async throws {
    let transport = HostedRankingsTransport()
    await transport.setSpotlightRank(instrument: "Solo_Guitar", accountId: "fixture-far-player", rank: 57)
    let session = try hostedRankingsSessionWithSelection(
        transport: transport, accountId: "fixture-far-player", displayName: "Fixture Far Player"
    )
    let size = CGSize(width: 402, height: 1200)
    let host = nativeHostedView(
        LeaderboardsScreen(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Your rank, 57th. Spotlight Player."], timeout: .seconds(60))
    _ = try nativeHostedPNG(
        image, filename: "leaderboards-spotlight-footer.png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Your rank, 57th. Spotlight Player."])
}

/// A selected player with no rank yet on a board shows the "not yet ranked" text.
@MainActor
@Test func leaderboardsScreenShowsUnrankedSpotlightText() async throws {
    let transport = HostedRankingsTransport()
    // No `setSpotlightRank` call: every single-account read 404s.
    let session = try hostedRankingsSessionWithSelection(
        transport: transport, accountId: "fixture-never-ranked", displayName: "Never Ranked"
    )
    let size = CGSize(width: 402, height: 1200)
    let host = nativeHostedView(
        LeaderboardsScreen(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Not yet ranked on Lead."], timeout: .seconds(60))
    _ = try nativeHostedPNG(
        image, filename: "leaderboards-spotlight-unranked.png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Not yet ranked on Lead."])
}

/// A failed single-account read shows the shared inline service status, not a crash.
@MainActor
@Test func leaderboardsScreenShowsSpotlightFailureInline() async throws {
    let transport = HostedRankingsTransport()
    await transport.setSpotlightFails(true)
    let session = try hostedRankingsSessionWithSelection(
        transport: transport, accountId: "fixture-far-player", displayName: "Fixture Far Player"
    )
    let size = CGSize(width: 402, height: 1200)
    let host = nativeHostedView(
        LeaderboardsScreen(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["The service is temporarily unavailable. Try again.", "Retry"], timeout: .seconds(60)
    )
    _ = try nativeHostedPNG(
        image, filename: "leaderboards-spotlight-failed.png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image,
        containing: ["Fixture Rank 1", "The service is temporarily unavailable. Try again."]
    )
}

/// The loading placeholder renders while the single-account read is still in flight.
@MainActor
@Test func leaderboardsScreenShowsSpotlightLoadingPlaceholder() async throws {
    let transport = HostedRankingsTransport()
    await transport.setSpotlightDelay(2_000)
    let session = try hostedRankingsSessionWithSelection(
        transport: transport, accountId: "fixture-far-player", displayName: "Fixture Far Player"
    )
    let size = CGSize(width: 402, height: 1200)
    let host = nativeHostedView(
        LeaderboardsScreen(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    // The page waits for every card, the delayed spotlight included, before it shows
    // anything (operator batch 6.41): a spinner first, then the finished cards.
    let loading = try await nativeHostedSettle(host, untilText: ["Loading Leaderboards"], timeout: .seconds(60))
    _ = try nativeHostedPNG(
        loading, filename: "leaderboards-spotlight-loading.png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    let image = try await nativeHostedSettle(host, untilText: ["Fixture Rank 1"], timeout: .seconds(60))
    assertRendersContent(host, image: image, containing: ["Fixture Rank 1"])
}

// MARK: - FullRankingsScreen selected-player spotlight

/// The Full Rankings board shows the same spotlight footer with a jump-to-page control.
@MainActor
@Test func fullRankingsScreenShowsSpotlightFooterWithJumpControl() async throws {
    let transport = HostedRankingsTransport()
    await transport.setSpotlightRank(instrument: "Solo_Guitar", accountId: "fixture-far-player", rank: 57)
    let session = try hostedRankingsSessionWithSelection(
        transport: transport, accountId: "fixture-far-player", displayName: "Fixture Far Player"
    )
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(
        FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore")
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .leaderboardsHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Your rank, 57th", "Jump to your page"], timeout: .seconds(60))
    _ = try nativeHostedPNG(
        image, filename: "full-rankings-spotlight-footer.png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Your rank, 57th", "Jump to your page"])
}

// MARK: - Quick Links (control states, Leaderboards adoption)

/// A single-section page hides its Quick Links entry point (`hidden-single-section`).
@MainActor
@Test func quickLinksHiddenWithOnlyOneSection() {
    let controller = QuickLinksController()
    controller.configure(title: "Leaderboards Quick Links", explicit: [
        LeaderboardsScreen.quickLink(for: Instrument.lead),
    ])
    #expect(!controller.isAvailable)
}

/// Leaderboards' full instrument + band section list is available and jumpable
/// (`menu-closed` → `jumped` → `active-section`), mirroring `LeaderboardsScreen`'s
/// own `quickLinkSections` composition.
@MainActor
@Test func quickLinksAvailableAndJumpUpdatesActiveSection() {
    let controller = QuickLinksController()
    let sections = Instrument.allCases.map { LeaderboardsScreen.quickLink(for: $0) }
        + BandType.allCases.map { LeaderboardsScreen.quickLink(for: $0) }
    controller.configure(title: "Leaderboards Quick Links", explicit: sections)
    #expect(controller.isAvailable)
    // With no scroll geometry reported yet, the first section wins by default
    // (`QuickLinks.naturalActive`: "With no section past the line, the first wins").
    #expect(controller.activeSection?.id == sections.first?.id)
    guard let target = sections.last else {
        Issue.record("Leaderboards quick links must be non-empty")
        return
    }
    controller.jump(to: target.id)
    #expect(controller.jumpTarget == target.id)
    #expect(controller.jumpSerial == 1)
    #expect(controller.activeSection?.id == target.id)
    // Jumping to an id the page never declared is a no-op (ignored, not a crash).
    controller.jump(to: "not-a-real-section")
    #expect(controller.jumpSerial == 1)
}

/// A collapsing (zero-height) viewport during teardown must not republish the active
/// section; a real geometry report still recomputes it (Lane W1 rail jitter).
@MainActor
@Test func quickLinksTeardownViewportKeepsActiveSection() {
    let controller = QuickLinksController()
    let sections = Instrument.allCases.prefix(3).map { LeaderboardsScreen.quickLink(for: $0) }
    controller.configure(title: "Leaderboards Quick Links", explicit: Array(sections))
    controller.reportViewport(height: 600)
    for (index, section) in sections.enumerated() {
        let top = Double(index) * 400 - 500
        controller.report(section.id, frame: QuickLinkFrame(minY: top, maxY: top + 400))
    }
    let active = controller.activeID
    #expect(active == sections[1].id)
    controller.reportViewport(height: 0)
    #expect(controller.activeID == active)
    controller.report(sections[1].id, frame: nil)
    #expect(controller.activeID != sections[1].id)
}

/// Discovered sections survive the all-at-once disappearance of a page teardown, so the
/// toolbar menu is not removed mid-pop; a real replacement applies at once and a real
/// emptying applies after `emptyDiscoveryDelay`.
@MainActor
@Test func quickLinksDiscoveryDefersTeardown() async {
    let controller = QuickLinksController()
    controller.configure(title: "Quick Links", explicit: nil)
    let first = [
        QuickLinkSection(id: "a", title: "A", icon: nil), QuickLinkSection(id: "b", title: "B", icon: nil),
    ]
    controller.discover(first)
    #expect(controller.isAvailable)
    controller.discover([])
    #expect(controller.sections == first)
    let second = [first[1], QuickLinkSection(id: "c", title: "C", icon: nil)]
    controller.discover(second)
    #expect(controller.sections.map(\.id) == ["b", "c"])
    // The cancelled empty discovery never fires.
    await controller.settleDeferredDiscovery()
    #expect(controller.sections.map(\.id) == ["b", "c"])
    controller.discover([])
    #expect(controller.sections.map(\.id) == ["b", "c"])
    await controller.settleDeferredDiscovery()
    #expect(controller.sections.isEmpty)
    #expect(!controller.isAvailable)
}
#endif
