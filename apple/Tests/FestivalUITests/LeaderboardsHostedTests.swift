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
        if url.pathComponents.count == 4, url.pathComponents[1] == "api",
           url.pathComponents[2] == "rankings" {
            let instrument = url.pathComponents[3]
            return HTTPResult(
                status: 200,
                data: try rankingsBody(instrument: instrument, rankBy: rankBy, page: page),
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        if url.pathComponents.count == 5, url.pathComponents[1] == "api",
           url.pathComponents[2] == "rankings", url.pathComponents[3] == "bands" {
            let bandType = url.pathComponents[4]
            return HTTPResult(
                status: 200,
                data: try bandRankingsBody(bandType: bandType, rankBy: rankBy, page: page),
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
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "leaderboards-overview.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
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
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "leaderboards-empty.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
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
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "full-rankings.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
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
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "band-rankings.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
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
#endif
