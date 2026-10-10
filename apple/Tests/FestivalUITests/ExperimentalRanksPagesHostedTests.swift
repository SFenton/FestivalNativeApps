#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Experimental Ranks on the rendered ranking pages (issue #541)
//
// Pattern `experimental-ranks` R2/R3: while Settings › Experimental Ranks is off a page
// offers no Rank By and loads Total Score, whatever metric was saved or deep-linked;
// turning it on offers the metrics in web order (bands without Max Score); turning it
// off again while an experimental board is open reloads that page as Total Score. The
// pure gate is `ExperimentalRanksTests`; these host the real pages and their real Rank
// By tools so a page that kept its menu, loaded a stale board or never reloaded fails.
//
// Account and band pages render beside the real iPhone tab-bar accessory
// (`PageToolsAccessoryBar`, as in `NavButtonAccessibilityTests`), where their Rank By
// page tool registers and opens as the inline choices sheet the accessory uses, so the
// choices and picks go through the shipped `RankByMenu`/`BandRankByMenu`. Rivals keeps
// its Rank By inline above the boards (`/duo` R2). The loopback fixture service
// answers; a recording transport keeps each request's `rankBy`.

/// Forwards to the loopback fixture service and records each request's URL.
private actor RankByRecordingTransport: HTTPTransport {
    private let inner = URLSessionHTTPTransport()
    private(set) var urls: [URL] = []

    func send(_ request: URLRequest) async throws -> HTTPResult {
        if let url = request.url { urls.append(url) }
        return try await inner.send(request)
    }
}

/// One recorded ranking read: its path and `rankBy`.
private struct RankByRequest: Equatable, CustomStringConvertible {
    let path: String
    let rankBy: String
    var description: String { "\(path)?rankBy=\(rankBy)" }
}

/// The recorded reads whose path matches, in order.
///
/// - Parameters:
///   - transport: The recording transport.
///   - pathMatches: Which paths count.
/// - Returns: Each matching read's path and `rankBy` (`totalscore` when absent, the
///   service default).
private func rankByRequests(
    _ transport: RankByRecordingTransport, where pathMatches: @Sendable (String) -> Bool
) async -> [RankByRequest] {
    await transport.urls.compactMap { url in
        guard pathMatches(url.path) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return RankByRequest(path: url.path, rankBy: items.first { $0.name == "rankBy" }?.value ?? "totalscore")
    }
}

/// A fixture session and a private settings store.
///
/// - Parameter player: Select `fixture-player-1` (Rivals needs a profile).
/// - Returns: The session, its recording transport and the store the pages' `@AppStorage`
///   reads (Reduce Motion on so loads settle without animation).
@MainActor
private func rankByFixture(player: Bool) async throws -> (FestivalSession, RankByRecordingTransport, UserDefaults) {
    let transport = RankByRecordingTransport()
    let client = try FestivalAPI(baseURL: try await RivalsMockService.shared.baseURL(), transport: transport)
    let storage = try #require(UserDefaults(suiteName: "fst.tests.experimental-ranks-pages.\(UUID().uuidString)"))
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    if player {
        storage.set(
            Data(#"{"accountId":"fixture-player-1","displayName":"Fixture Player 1"}"#.utf8),
            forKey: SelectedPlayerIdentity.storageKey
        )
    }
    return (FestivalSession(factory: { client }, selectionStorage: storage), transport, storage)
}

/// Host a page in a navigation stack above the real tab-bar accessory bar.
///
/// - Parameters:
///   - page: The page.
///   - session: Its session.
///   - storage: The settings store the page and its tools read.
///   - registry: The accessory's registry the page's tools register in.
///   - height: Window height (tall enough for the content a test reads).
/// - Returns: The retained host and window.
@MainActor
private func hostRankByPage(
    _ page: some View, session: FestivalSession, storage: UserDefaults, registry: PageToolsRegistry?,
    height: CGFloat = 900
) -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow) {
    let size = CGSize(width: 402, height: height)
    let host = nativeHostedView(AnyView(
        VStack(spacing: 0) {
            NavigationStack { page.pageToolsScope() }
            if let registry {
                PageToolsAccessoryBar(registry: registry)
                    .frame(height: NavButtonAccessibilityTests.accessoryHeight)
                    .buttonStyle(.borderless)
            }
        }
        .environment(\.pageToolsRegistry, registry)
        .environment(\.festivalSession, session)
        .defaultAppStorage(storage)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark)
    ), size: size)
    return (host, nativeHostedWindow(host, size: size))
}

/// Wait until `ready` holds, recording an issue when it never does.
@MainActor
private func waitFor(
    _ host: NSView, _ what: String, sourceLocation: SourceLocation = #_sourceLocation,
    until ready: @MainActor () async -> Bool
) async throws {
    var budget = NativeHostedPollBudget(.seconds(20))
    while !(await ready()) {
        if budget.isExhausted {
            Issue.record("Timed out waiting for \(what)", sourceLocation: sourceLocation)
            return
        }
        host.layoutSubtreeIfNeeded()
        try await budget.sleep(for: .milliseconds(50))
    }
}

/// Press a page's Rank By tool in the accessory and return the choices sheet it opens,
/// then clear it.
///
/// - Parameters:
///   - identifier: The Rank By tool's identifier.
///   - registry: The accessory's registry.
///   - host: The host.
/// - Returns: The choices, in menu order.
@MainActor
private func openRankBy(
    _ identifier: String, registry: PageToolsRegistry, host: NSView,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> [PageToolMenuChoice] {
    let tool = try #require(nativeHostedAccessibilityElement(identifier, in: host), sourceLocation: sourceLocation)
    _ = tool.perform(NSSelectorFromString("accessibilityPerformPress"))
    try await waitFor(host, "the Rank By choices", sourceLocation: sourceLocation) { registry.inlineMenu != nil }
    let menu = try #require(registry.inlineMenu, sourceLocation: sourceLocation)
    #expect(menu.title == "Rank By", sourceLocation: sourceLocation)
    return menu.choices
}

/// Pick a choice the way the inline sheet does: close, then run it.
@MainActor
private func pick(_ id: String, from choices: [PageToolMenuChoice], registry: PageToolsRegistry) throws {
    let choice = try #require(choices.first { $0.id == id })
    registry.choose(choice)
    registry.inlineMenuDismissed()
}

private let accountRankByID = "fst.rankings.rank-by-menu"
private let bandRankByID = "fst.band-rankings.rank-by-menu"
private let accountChoiceIDs = ["totalscore", "adjusted", "weighted", "fcrate", "maxscore"].map { "fst.rankings.rank-by.\($0)" }
private let bandChoiceIDs = ["totalscore", "adjusted", "weighted", "fcrate"].map { "fst.band-rankings.rank-by.\($0)" }

/// Whether the host shows an element with `identifier`.
@MainActor
private func shows(_ identifier: String, in host: NSView) -> Bool {
    nativeHostedAccessibilityElement(identifier, in: host) != nil
}

/// Band Detail's Statistics rank tiles, in reading order (the Adjusted, Weighted and FC
/// Rate tiles show only with the switch on, #555).
@MainActor
private func bandRankTiles(in host: NSView) -> [String] {
    let prefix = "\(BandDetailScreen.statIdentifierPrefix).statistics."
    return nativeHostedAccessibility(host).identifiers
        .filter { $0.hasPrefix(prefix) && $0.hasSuffix("-rank") }
        .map { String($0.dropFirst(prefix.count)) }
}

private let bandRankTilesOff = ["total-score-rank", "best-song-rank", "avg-rank"]
private let bandRankTilesOn = ["adjusted-rank", "weighted-rank", "fc-rate-rank"] + bandRankTilesOff

// MARK: - Tests

@MainActor
@Suite(.serialized) struct ExperimentalRanksPagesHostedTests {
    /// Full Rankings deep-linked to Weighted: Total Score and no Rank By while off; the
    /// route's Weighted board and the ordered account choices once on; Max Score when
    /// picked; Total Score again, with Rank By withdrawn, when turned off.
    @Test func fullRankingsFollowsTheSwitch() async throws {
        let (session, transport, storage) = try await rankByFixture(player: false)
        let registry = PageToolsRegistry()
        let (host, window) = hostRankByPage(
            FullRankingsScreen(session: session, instrument: .lead, rankBy: "weighted"),
            session: session, storage: storage, registry: registry
        )
        defer { window.orderOut(nil) }
        let isBoard: @Sendable (String) -> Bool = { $0 == "/api/rankings/Solo_Guitar" }

        try await waitFor(host, "the Total Score board") { await !rankByRequests(transport, where: isBoard).isEmpty }
        try await nativeHostedSettle(host, untilText: ["Fixture"], excluding: ["Loading"])
        #expect(await rankByRequests(transport, where: isBoard).map(\.rankBy).allSatisfy { $0 == "totalscore" },
                "a deep-linked experimental metric loads Total Score while off")
        #expect(!shows(accountRankByID, in: host), "no Rank By while off")

        storage.set(true, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By") { shows(accountRankByID, in: host) }
        try await waitFor(host, "the Weighted board") {
            await rankByRequests(transport, where: isBoard).last?.rankBy == "weighted"
        }
        let choices = try await openRankBy(accountRankByID, registry: registry, host: host)
        #expect(choices.map(\.id) == accountChoiceIDs, "web order")
        #expect(choices.first { $0.isSelected }?.id == "fst.rankings.rank-by.weighted")
        try pick("fst.rankings.rank-by.maxscore", from: choices, registry: registry)
        try await waitFor(host, "the Max Score board") {
            await rankByRequests(transport, where: isBoard).last?.rankBy == "maxscore"
        }

        let before = await rankByRequests(transport, where: isBoard).count
        storage.set(false, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By withdrawn") { !shows(accountRankByID, in: host) }
        try await waitFor(host, "the Total Score reload") {
            await rankByRequests(transport, where: isBoard).count > before
        }
        try await nativeHostedSettle(host, untilText: ["Fixture"], excluding: ["Loading"])
        let after = await rankByRequests(transport, where: isBoard).dropFirst(before)
        #expect(!after.isEmpty && after.allSatisfy { $0.rankBy == "totalscore" }, "\(Array(after))")
    }

    /// Leaderboards with a saved FC Rate: every card loads Total Score and there is no
    /// Rank By while off; on restores the saved metric with the ordered choices; off
    /// again reloads every card as Total Score and keeps the saved choice for later.
    @Test func leaderboardsFollowsTheSwitch() async throws {
        let (session, transport, storage) = try await rankByFixture(player: false)
        storage.set("fcrate", forKey: "fst.leaderboards.rankBy")
        let registry = PageToolsRegistry()
        let (host, window) = hostRankByPage(
            LeaderboardsScreen(session: session), session: session, storage: storage, registry: registry
        )
        defer { window.orderOut(nil) }
        let isAccountBoard: @Sendable (String) -> Bool = {
            $0.hasPrefix("/api/rankings/") && !$0.hasPrefix("/api/rankings/bands/") && $0.split(separator: "/").count == 3
        }

        try await waitFor(host, "the cards") { await !rankByRequests(transport, where: isAccountBoard).isEmpty }
        try await nativeHostedSettle(host, untilText: ["Fixture"], excluding: ["Loading"])
        #expect(await rankByRequests(transport, where: isAccountBoard).allSatisfy { $0.rankBy == "totalscore" },
                "a saved experimental metric loads Total Score while off")
        #expect(!shows(accountRankByID, in: host), "no Rank By while off")

        storage.set(true, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By") { shows(accountRankByID, in: host) }
        try await waitFor(host, "the saved FC Rate boards") {
            await rankByRequests(transport, where: isAccountBoard).last?.rankBy == "fcrate"
        }
        let choices = try await openRankBy(accountRankByID, registry: registry, host: host)
        #expect(choices.map(\.id) == accountChoiceIDs, "web order")
        #expect(choices.first { $0.isSelected }?.id == "fst.rankings.rank-by.fcrate")
        registry.inlineMenuDismissed()

        try await nativeHostedSettle(host, untilText: ["Fixture"], excluding: ["Loading"])
        let before = await rankByRequests(transport, where: isAccountBoard).count
        storage.set(false, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By withdrawn") { !shows(accountRankByID, in: host) }
        try await waitFor(host, "the Total Score reload") {
            await rankByRequests(transport, where: isAccountBoard).count > before
        }
        try await nativeHostedSettle(host, untilText: ["Fixture"], excluding: ["Loading"])
        let after = await rankByRequests(transport, where: isAccountBoard).dropFirst(before)
        #expect(!after.isEmpty && after.allSatisfy { $0.rankBy == "totalscore" }, "\(Array(after))")
        #expect(storage.string(forKey: "fst.leaderboards.rankBy") == "fcrate", "the saved choice returns with the switch")
    }

    /// Band Rankings: Total Score and no Rank By while off; on offers the band metrics
    /// (no Max Score) in web order; an FC Rate pick reloads as Total Score when turned off.
    @Test func bandRankingsFollowsTheSwitch() async throws {
        let (session, transport, storage) = try await rankByFixture(player: false)
        let registry = PageToolsRegistry()
        let (host, window) = hostRankByPage(
            BandRankingsScreen(session: session, bandType: "Band_Duets"),
            session: session, storage: storage, registry: registry
        )
        defer { window.orderOut(nil) }
        let isBoard: @Sendable (String) -> Bool = { $0 == "/api/rankings/bands/Band_Duets" }

        try await waitFor(host, "the band board") { await !rankByRequests(transport, where: isBoard).isEmpty }
        try await nativeHostedSettle(host, untilText: ["Member A"], excluding: ["Loading"])
        #expect(!shows(bandRankByID, in: host), "no Rank By while off")

        storage.set(true, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By") { shows(bandRankByID, in: host) }
        let choices = try await openRankBy(bandRankByID, registry: registry, host: host)
        #expect(choices.map(\.id) == bandChoiceIDs, "web order, no Max Score for bands")
        try pick("fst.band-rankings.rank-by.fcrate", from: choices, registry: registry)
        try await waitFor(host, "the FC Rate board") {
            await rankByRequests(transport, where: isBoard).last?.rankBy == "fcrate"
        }
        try await nativeHostedSettle(host, untilText: ["Member A"], excluding: ["Loading"])

        let before = await rankByRequests(transport, where: isBoard).count
        storage.set(false, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By withdrawn") { !shows(bandRankByID, in: host) }
        try await waitFor(host, "the Total Score reload") {
            await rankByRequests(transport, where: isBoard).count > before
        }
        let after = await rankByRequests(transport, where: isBoard).dropFirst(before)
        #expect(!after.isEmpty && after.allSatisfy { $0.rankBy == "totalscore" }, "\(Array(after))")
    }
    /// Band Detail opens on Adjusted only with experimental ranks (web `BandPage`): while
    /// off it has no Rank By and Band Statistics shows only the Total Score rank tiles; on,
    /// Rank By offers the band metrics in web order with Adjusted picked and the Adjusted,
    /// Weighted and FC Rate rank tiles appear; off again, Rank By and those tiles go.
    @Test func bandDetailFollowsTheSwitch() async throws {
        let (session, _, storage) = try await rankByFixture(player: false)
        let registry = PageToolsRegistry()
        let (host, window) = hostRankByPage(
            BandDetailScreen(
                session: session, bandId: "fixture-band-1", name: "Band 1 Member A + Band 1 Member B",
                bandType: "Band_Duets", teamKey: "fixture-team-1"
            ),
            session: session, storage: storage, registry: registry, height: 2400
        )
        defer { window.orderOut(nil) }

        try await waitFor(host, "the Statistics tiles") { bandRankTiles(in: host) == bandRankTilesOff }
        #expect(bandRankTiles(in: host) == bandRankTilesOff, "Total Score rank tiles only while off")
        #expect(!shows(bandRankByID, in: host), "no Rank By while off")

        storage.set(true, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By") { shows(bandRankByID, in: host) }
        try await waitFor(host, "the experimental rank tiles") { bandRankTiles(in: host) == bandRankTilesOn }
        #expect(bandRankTiles(in: host) == bandRankTilesOn)
        let choices = try await openRankBy(bandRankByID, registry: registry, host: host)
        #expect(choices.map(\.id) == bandChoiceIDs, "web order, no Max Score for bands")
        #expect(choices.first { $0.isSelected }?.id == "fst.band-rankings.rank-by.adjusted")
        registry.inlineMenuDismissed()

        storage.set(false, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By withdrawn") { !shows(bandRankByID, in: host) }
        try await waitFor(host, "the Total Score tiles") { bandRankTiles(in: host) == bandRankTilesOff }
        #expect(bandRankTiles(in: host) == bandRankTilesOff)
    }

    /// Rivals' Leaderboard tab: no Rank By and Total Score boards while off, even when
    /// opened on FC Rate (web `?tab=leaderboard&rankBy=fcrate`); on shows Rank By naming
    /// FC Rate and loads FC Rate boards; off again withdraws it and reloads Total Score.
    @Test func rivalsLeaderboardFollowsTheSwitch() async throws {
        let (session, transport, storage) = try await rankByFixture(player: true)
        let (host, window) = hostRankByPage(
            RivalsScreen(session: session, tab: .leaderboard, rankBy: .fcrate),
            session: session, storage: storage, registry: nil
        )
        defer { window.orderOut(nil) }
        let isBoard: @Sendable (String) -> Bool = {
            $0 == "/api/player/fixture-player-1/leaderboard-rivals/Solo_Guitar"
        }
        let rankByID = "fst.rivals.rankBy"

        try await waitFor(host, "the Lead board") { await !rankByRequests(transport, where: isBoard).isEmpty }
        try await nativeHostedSettle(host, untilText: ["Lead Rivals"], excluding: ["Loading"])
        #expect(await rankByRequests(transport, where: isBoard).allSatisfy { $0.rankBy == "totalscore" },
                "an opening experimental metric loads Total Score while off")
        #expect(!shows(rankByID, in: host), "no Rank By while off")

        storage.set(true, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By") { shows(rankByID, in: host) }
        try await waitFor(host, "the FC Rate board") {
            await rankByRequests(transport, where: isBoard).last?.rankBy == "fcrate"
        }
        let menu = try #require(macAccessibilityTree(host).first { $0.identifier == rankByID })
        #expect(menu.role == "AXMenuButton")
        #expect(menu.spokenName == "FC Rate", "names the metric in effect: \(menu)")
        try await nativeHostedSettle(host, untilText: ["Lead Rivals"], excluding: ["Loading"])

        let before = await rankByRequests(transport, where: isBoard).count
        storage.set(false, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By withdrawn") { !shows(rankByID, in: host) }
        try await waitFor(host, "the Total Score reload") {
            await rankByRequests(transport, where: isBoard).count > before
        }
        let after = await rankByRequests(transport, where: isBoard).dropFirst(before)
        #expect(!after.isEmpty && after.allSatisfy { $0.rankBy == "totalscore" }, "\(Array(after))")
    }

    /// Rivals opened on the Song tab (the default): pressing Leaderboard while off shows
    /// no Rank By and Total Score boards; turning the switch on adds Rank By, on Total Score.
    @Test func rivalsLeaderboardTabOffersRankByOnlyWhenOn() async throws {
        let (session, transport, storage) = try await rankByFixture(player: true)
        let (host, window) = hostRankByPage(
            RivalsScreen(session: session), session: session, storage: storage, registry: nil
        )
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Lead Rivals"], excluding: ["Loading"])
        let segment = try #require(nativeHostedAccessibilityElement(in: host) {
            nativeHostedAccessibilityString($0, "accessibilityLabel") == "Leaderboard"
                || nativeHostedAccessibilityString($0, "accessibilityTitle") == "Leaderboard"
        })
        _ = segment.perform(NSSelectorFromString("accessibilityPerformPress"))
        let isLeaderboard: @Sendable (String) -> Bool = { $0.contains("/leaderboard-rivals/") }
        try await waitFor(host, "the Leaderboard tab") { await !rankByRequests(transport, where: isLeaderboard).isEmpty }
        try await nativeHostedSettle(host, untilText: ["Lead Rivals"], excluding: ["Loading"])
        #expect(!shows("fst.rivals.rankBy", in: host), "no Rank By while off")
        #expect(await rankByRequests(transport, where: isLeaderboard).allSatisfy { $0.rankBy == "totalscore" })

        storage.set(true, forKey: ExperimentalRanks.storageKey)
        try await waitFor(host, "Rank By") { shows("fst.rivals.rankBy", in: host) }
        #expect(macAccessibilityTree(host).first { $0.identifier == "fst.rivals.rankBy" }?.spokenName == "Total Score")
    }
}
#endif
