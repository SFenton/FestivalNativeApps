#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import FestivalDesign
@testable import FestivalCore
@testable import FestivalUI

// MARK: - In-card View All accessibility (issue #382, backfilled by #500)

/// #382 moved every purple "View All" call to action inside its group card as the
/// ``FestivalGlassSection`` `action` (view-all-cta R1). Rivals' View All Rivals and
/// Compete's View Full Leaderboard (`RivalsViewAllAccessibilityTests`,
/// `CompeteLeaderboardsAccessibilityTests`), Song Detail's band previews
/// (`SongDetailBandColumnsAccessibilityTests`), Profile's Bands groups
/// (`ProfileBandsCardAccessibilityTests`) and the transparency modes
/// (`MaterialCardControlsAccessibilityTests`) already have accessibility tests. These pin
/// the remaining consumers #382 moved: Song Detail's instrument preview (View Full
/// Leaderboard), Song Detail's Score History (View All Scores), the Leaderboards overview
/// (View all rankings (N)) and Rival Detail's category cards (View All).
///
/// For each card, at the default and the largest accessibility size:
/// - name, role and state: one button, named label first and then its card (R4, WCAG
///   2.5.3), read once, never selected;
/// - reading order: the card's heading, then its rows, then the button;
/// - target: at least 44 pt tall, spanning the card less its 10 pt action inset, below
///   the last row inside the card (R1, R3);
/// - operable without a pointer: AXPress (VoiceOver, Voice Control, Switch Control and
///   Full Keyboard Access) opens the card's full list (R8).
///
/// macOS has no Dynamic Type, so `InCardViewAllAccessibilityJourneyTests` is the iPhone
/// and iPad text-growth and audit evidence.
///
/// HIG Accessibility: "Provide VoiceOver descriptions for all interface elements" and the
/// iOS/iPadOS default control size "44×44pt"; HIG Buttons: "Minimum hit region: 44x44 pt".
@MainActor
@Suite(.serialized)
struct InCardViewAllAccessibilityTests {
    // MARK: - Cards

    /// The #382 consumers without an accessibility test of their own.
    enum Card: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case songPreview, scoreHistory, leaderboards, rivalDetail

        var testDescription: String { rawValue }

        /// The button's identifier.
        var buttonID: String {
            switch self {
            case .songPreview: "fst.song-detail.leaderboard.\(Instrument.lead.rawValue)"
            case .scoreHistory: "fst.song-detail.history.view-all"
            case .leaderboards: "fst.leaderboards.card.\(Instrument.lead.rawValue).view-all"
            case .rivalDetail: "fst.rival-detail.category.closest_battles.view-all"
            }
        }

        /// The visible label.
        var title: String {
            switch self {
            case .songPreview: "View Full Leaderboard"
            case .scoreHistory: "View All Scores"
            case .leaderboards: RankingsCountText.viewAllRankings(totalAccounts: 3)
            case .rivalDetail: "View All"
            }
        }

        /// The card the spoken name adds after the label.
        var card: String {
            switch self {
            case .songPreview, .leaderboards: Instrument.lead.label
            case .scoreHistory: "\(Instrument.lead.label) Score History"
            case .rivalDetail: "Closest Battles"
            }
        }

        /// The accessible name: the visible label, then the card (R4).
        var spokenName: String { PurpleActionName.spoken(title, card: card) }

        /// The card's heading as VoiceOver reads it.
        func isHeading(_ node: MacAXNode) -> Bool {
            switch self {
            case .songPreview: node.identifier == "fst.song-detail.card-header.\(Instrument.lead.rawValue)"
            case .scoreHistory: node.spokenName.hasPrefix("Score History")
            case .leaderboards: node.spokenName == Instrument.lead.label
            case .rivalDetail: node.spokenName.hasPrefix("Closest Battles")
            }
        }

        /// One of the card's rows.
        func isRow(_ node: MacAXNode) -> Bool {
            switch self {
            case .songPreview: node.identifier.hasPrefix("fst.song-detail.preview-row.\(Instrument.lead.rawValue).")
            case .scoreHistory: node.identifier.hasPrefix("fst.song-detail.history.row.")
            case .leaderboards: node.identifier.hasPrefix("fst.rankings.row.")
            case .rivalDetail: node.spokenName.contains(", you rank ")
            }
        }

        /// Rows the fixture puts in the card.
        var rowCount: ClosedRange<Int> {
            switch self {
            case .songPreview, .leaderboards: 3...3
            case .scoreHistory: SongScoreHistoryModel.listLimit...SongScoreHistoryModel.listLimit
            case .rivalDetail: 1...5
            }
        }

        /// Flush rows span the card, so the button sits exactly the action inset inside them.
        var flushRows: Bool { self != .rivalDetail }

        /// Whether a pushed route is the card's full list.
        func opens(_ route: AppRoute) -> Bool {
            switch (self, route) {
            case let (.songPreview, .songLeaderboard(_, instrument, page, _)): instrument == .lead && page == 1
            case let (.scoreHistory, .playerHistory(_, instrument)): instrument == .lead
            case let (.leaderboards, .fullRankings(instrument, _, _, _)): instrument == .lead
            case let (.rivalDetail, .rivalry(_, mode, _, _)): mode == "closest_battles"
            default: false
            }
        }
    }

    // MARK: - Hosting

    /// Routes the hosted stack pushed.
    @MainActor final class OpenedRoutes {
        var routes: [AppRoute] = []
    }

    /// One hosted card or page.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let opened: OpenedRoutes
        let storage: UserDefaults
        let suite: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suite)
        }
    }

    /// Every instrument's Settings visibility key.
    static let allInstrumentKeys = [
        "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
        "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
        "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
    ]

    static let size = CGSize(width: 402, height: 1400)

    /// Settings the hosted views read: Reduce Motion (offscreen load fades never advance).
    static func storage() throws -> (UserDefaults, String) {
        let suite = "fst-in-card-view-all-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        return (storage, suite)
    }

    /// Host a card's page at a Dynamic Type size and wait for its button.
    ///
    /// - Parameters:
    ///   - card: The consumer to host.
    ///   - typeSize: Dynamic Type size for the whole page.
    /// - Returns: The settled host, its window and the routes it pushes.
    /// - Throws: A missing fixture or an unsettled page.
    static func host(_ card: Card, _ typeSize: DynamicTypeSize) async throws -> Hosted {
        let (storage, suite) = try storage()
        let page: AnyView
        switch card {
        case .songPreview:
            // No client: the card renders from its loaded state only.
            let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
            let song = try previewSong()
            let leaderboard = try previewLeaderboard()
            page = AnyView(ScrollView {
                SongScorePreview(song: song, instrument: .lead, session: session, initialState: .loaded(leaderboard))
                    .padding(16)
            })
        case .scoreHistory:
            let transport = HostedHistoryTransport()
            await transport.setExtraLeadScores([500_000, 400_000, 300_000])
            let session = historySession(transport, storage: storage)
            let entries = try await session.songHistory(accountId: "fixture-1", songId: historySong.songId)
                .response.history
            page = AnyView(ScrollView {
                SongScoreHistorySection(song: historySong, entries: entries, pool: [.lead], instrument: .constant(nil))
                    .padding(16)
            })
        case .leaderboards:
            let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: HostedRankingsTransport())
            page = AnyView(LeaderboardsScreen(session: FestivalSession(factory: { client })))
        case .rivalDetail:
            let baseURL = try await RivalsMockService.shared.baseURL()
            let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
            let identity = ["accountId": "fixture-riv", "displayName": "Fixture Viewer"]
            storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
            for key in allInstrumentKeys { storage.set(key == "fst.settings.showLead", forKey: key) }
            let session = FestivalSession(factory: { client }, selectionStorage: storage)
            page = AnyView(RivalDetailScreen(
                session: session, rivalId: "f1c749eb07c32578cfa3e59ec38c03a8", name: "Fixture Rival Golf",
                scope: .song(instruments: ["Solo_Guitar"])
            ))
        }
        let opened = OpenedRoutes()
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    page.navigationDestination(for: AppRoute.self) { route in
                        Text("Destination").onAppear { opened.routes.append(route) }
                    }
                }
                .frame(width: size.width, height: size.height)
                .background(BrandTokens.appBackground)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityFrame(card.buttonID, in: host) != nil
                && macAccessibilityTree(host).filter { $0.isElement && card.isRow($0) }.count >= card.rowCount.lowerBound
        }
        return Hosted(host: host, window: window, opened: opened, storage: storage, suite: suite)
    }

    // MARK: - Fixtures

    /// A catalogue song for the instrument preview.
    static func previewSong() throws -> Song {
        try JSONDecoder().decode(Song.self, from: Data("""
        {"songId":"fixture-1","title":"Fixture 1","artist":"Fixture Artist","year":2026,
         "difficulty":{"guitar":1,"bass":3}}
        """.utf8))
    }

    /// Lead's top three of 26 for the instrument preview.
    static func previewLeaderboard() throws -> LeaderboardPayload {
        let rows = (1...3).map { rank in
            #"{"accountId":"fixture-player-\#(rank)","displayName":"Player \#(rank)","score":90000,"rank":\#(rank)}"#
        }.joined(separator: ",")
        let result = try JSONDecoder().decode(LeaderboardResponse.self, from: Data("""
        {"songId":"fixture-1","instrument":"Solo_Guitar","count":3,"localEntries":26,"totalEntries":26,
         "entries":[\(rows)]}
        """.utf8))
        try result.validate(songId: "fixture-1", instrument: .lead)
        return LeaderboardPayload(page: 1, leaderboard: result, publicationId: 7, observedPublicationId: 7, isStale: false)
    }

    /// The song `HostedHistoryTransport` serves six Lead scores for.
    static let historySong = Song(
        songId: "fixture-song", title: "Fixture Anthem", artist: "The Fixtures", album: nil,
        year: 2024, durationSeconds: 180, albumArt: nil, difficulty: nil,
        pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
    )

    /// `fixture-1` selected over the history transport.
    static func historySession(_ transport: HostedHistoryTransport, storage: UserDefaults) -> FestivalSession {
        let client = try! FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
        storage.set(
            Data(#"{"accountId":"fixture-1","displayName":"Fixture Player"}"#.utf8),
            forKey: SelectedPlayerIdentity.storageKey
        )
        return FestivalSession(factory: { client }, selectionStorage: storage)
    }

    // MARK: - Assertions

    static func dump(_ nodes: [MacAXNode]) -> String { nodes.map(\.description).joined(separator: "\n") }

    /// One button, named label first and then its card, read once and never selected.
    static func expectNameRoleAndState(_ card: Card, _ host: NSView, _ context: String) throws {
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "in-card-view-all-\(context)")
        let elements = nodes.filter(\.isElement)
        let matches = elements.filter { $0.identifier == card.buttonID }
        try #require(matches.count == 1, "\(context): one \(card.buttonID) in\n\(dump(nodes))")
        let button = matches[0]
        #expect(button.role == NSAccessibility.Role.button.rawValue, "\(context): a button: \(button)")
        #expect(button.spokenName == card.spokenName, "\(context): label first, then the card: \(button)")
        #expect(button.spokenName.hasPrefix(card.title), "\(context): the name starts with the visible label")
        #expect(!button.selected, "\(context): a push button has no selected state: \(button)")
        #expect(button.isEnabled, "\(context): enabled: \(button)")
        // The label is read once, through the button, not again as loose text.
        #expect(elements.filter { $0.spokenName == card.spokenName }.count == 1, "\(context): read once")
        #expect(!elements.contains { $0.role == "AXStaticText" && $0.spokenName == card.title },
                "\(context): the visible label is not a separate element:\n\(dump(elements))")
        #expect(macAccessibilityFindings(nodes) == [], "\(context): unnamed controls or images")
    }

    /// The card's heading, then its rows, then the button.
    static func expectReadingOrder(_ card: Card, _ host: NSView, _ context: String) throws {
        let order = macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
        let heading = try #require(order.firstIndex(where: card.isHeading), "\(context): heading in\n\(dump(order))")
        let button = try #require(order.firstIndex { $0.identifier == card.buttonID }, "\(context): button")
        #expect(heading < button, "\(context): the heading reads before the button:\n\(dump(order))")
        let rows = order.indices.filter { card.isRow(order[$0]) && $0 > heading }
        let inCard = rows.filter { $0 < button }
        #expect(card.rowCount.contains(inCard.count), "\(context): \(inCard.count) rows between heading and button:\n\(dump(order))")
        // Rows after the button belong to the next card, after that card's own heading.
        if let next = rows.first(where: { $0 > button }) {
            #expect(order[(button + 1)..<next].contains { $0.role == "AXHeading" },
                    "\(context): later rows follow the next card's heading:\n\(dump(order))")
        }
    }

    /// At least 44 pt tall, spanning the card less its action inset, below the last row.
    static func expectTarget(_ card: Card, _ host: NSView, _ context: String) throws {
        let inset = FestivalGlassSection<EmptyView, EmptyView>.actionInset
        let button = try #require(nativeHostedAccessibilityFrame(card.buttonID, in: host))
        #expect(button.height >= 44 - 0.5, "\(context): at least 44 pt tall: \(button)")
        let rowFrames = macAccessibilityRowFrames(card, host).filter { $0.maxY <= button.minY + 0.5 }
        let last = try #require(rowFrames.max { $0.maxY < $1.maxY }, "\(context): a row above the button")
        #expect(button.minY >= last.maxY - 0.5, "\(context): below the last row: \(button) under \(last)")
        #expect(button.minY - last.maxY <= inset + 24, "\(context): inside the card, right after its rows: \(button) under \(last)")
        if card.flushRows {
            // Flush rows span the card: the button is inset by the action inset on each side.
            #expect(abs(button.minX - last.minX - inset) <= 1, "\(context): leading inset: \(button) vs \(last)")
            #expect(abs(last.maxX - button.maxX - inset) <= 1, "\(context): trailing inset: \(button) vs \(last)")
            #expect(abs(button.minY - last.maxY - inset) <= 1, "\(context): top inset: \(button) vs \(last)")
        } else {
            // The page's 16 pt margins and the card's action inset on each side.
            #expect(button.width >= size.width - 32 - 2 * inset - 1, "\(context): spans its card: \(button)")
        }
    }

    /// The frames of the card's rows, top to bottom.
    ///
    /// Reads title and value as well as label: non-link rows (Rival Detail songs missing
    /// from the catalogue) are static text whose words are its value.
    static func macAccessibilityRowFrames(_ card: Card, _ host: NSView) -> [CGRect] {
        var frames: [CGRect] = []
        var seen = Set<ObjectIdentifier>()
        func read(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }
        func walk(_ node: Any, depth: Int) {
            guard depth < 80, let object = node as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            if (read(object, "isAccessibilityElement") as? Bool) == true {
                let row = MacAXNode(
                    depth: 0, role: "", subrole: "",
                    label: nativeHostedAccessibilityString(object, "accessibilityLabel"),
                    title: nativeHostedAccessibilityString(object, "accessibilityTitle"),
                    value: nativeHostedAccessibilityString(object, "accessibilityValue"),
                    identifier: nativeHostedAccessibilityString(object, "accessibilityIdentifier"),
                    selected: false, help: "", isElement: true
                )
                if card.isRow(row), let frame = nativeHostedAccessibilityFrame(of: object, in: host) {
                    frames.append(frame)
                }
            }
            for key in ["accessibilityChildrenInNavigationOrder", "accessibilityChildren"] {
                for child in (read(object, key) as? [Any]) ?? [] { walk(child, depth: depth + 1) }
            }
            if let view = object as? NSView {
                for subview in view.subviews { walk(subview, depth: depth + 1) }
            }
        }
        walk(host, depth: 0)
        return frames.sorted { $0.minY < $1.minY }
    }

    /// Press the button the way VoiceOver, Voice Control, Switch Control and Full Keyboard
    /// Access do (AXPress) and wait for the pushed route.
    static func expectPressOpensFullList(_ card: Card, _ hosted: Hosted, _ context: String) async throws {
        let element = try #require(nativeHostedAccessibilityElement(card.buttonID, in: hosted.host))
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(element.responds(to: press), "\(context): offers a press action")
        _ = element.perform(press)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            !hosted.opened.routes.isEmpty
        }
        let route = try #require(hosted.opened.routes.first, "\(context): AXPress pushed nothing")
        #expect(card.opens(route), "\(context): AXPress opens the card's full list, not \(route)")
    }

    // MARK: - Tests

    /// Each in-card button is one named button read after its card's heading and rows,
    /// a full-width 44 pt target inside the card, at the default and largest sizes.
    @Test(arguments: Card.allCases, [DynamicTypeSize.large, .accessibility5])
    func inCardViewAllIsNamedOrderedAndSized(_ card: Card, _ typeSize: DynamicTypeSize) async throws {
        let hosted = try await Self.host(card, typeSize)
        defer { hosted.close() }
        let context = "\(card.rawValue)-\(typeSize == .large ? "large" : "ax5")"
        try Self.expectNameRoleAndState(card, hosted.host, context)
        try Self.expectReadingOrder(card, hosted.host, context)
        try Self.expectTarget(card, hosted.host, context)
    }

    /// AXPress on each in-card button opens its full list (view-all-cta R8).
    @Test(arguments: Card.allCases)
    func inCardViewAllOpensItsListThroughAXPress(_ card: Card) async throws {
        let hosted = try await Self.host(card, .large)
        defer { hosted.close() }
        try await Self.expectPressOpensFullList(card, hosted, card.rawValue)
    }
}
#endif
