#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Compete "your rank" row accessibility (issue #493, for #370)

/// #370 gave each Compete leaderboard preview the selected player's own highlighted row
/// when they rank outside its top rows (web `CompetePage` `playerEntry`), and made it the
/// leaderboard-row R7 Compete variant: it opens that board's full rankings on the page
/// holding their rank and reveals their row ("Jump to your position"), while every other
/// row keeps opening a profile (`CompeteInstrumentLeaderboardSection.spotlightRow`,
/// ``CompetePreviewSpotlight``).
///
/// These hosted checks (macOS host, `apple-ci`) pin that row for VoiceOver, Voice Control
/// and Switch Control on every Apple platform, since the card is the same SwiftUI on
/// iPhone, iPad, iPhone Duo and Mac, on the stacked page and on the Duo inner display's
/// Leaderboards carousel. The fixture viewer `fixture-riv-ranked` (`tools/mock_service.py`)
/// ranks 45th of 60 on every board, so each card (the Lead + Bass combo, Lead, Bass) appends
/// it. Each card holds exactly one such row: one link (or button) named "Your rank, 45th.
/// Jump to your position.", read after the card's top rows and before its View Full
/// Leaderboard, drawn there too, as wide as the card and at least 44 pt tall; its row
/// content and chevron read only through it; the top rows keep their own names. The
/// largest accessibility size stacks the row taller and changes none of that, nor do fades
/// with motion, system Reduce Motion or the app's Reduce Motion. Pressing it (AXPress, as
/// VoiceOver, Voice Control and Switch Control do; a hosted test cannot give a SwiftUI
/// button Tab focus, #461) pushes the card's full board on page 2 with the row revealed
/// (`focusSelected`), while a top row still pushes that player's profile. The reveal on
/// arrival, with and without Reduce Motion, is `SelectedRowRevealHostedTests`
/// (`fullRankingsArrival`); macOS keeps the font size, so the iPhone journey
/// `CompeteAccessibilityJourneyTests.testYourRankRowIsAccessibleAtAX5` proves real AX5
/// growth, whole text, reach and the system audit.
///
/// HIG Accessibility: "Describe the interface and content for VoiceOver" and the iOS/iPadOS
/// 44×44 pt default control size; HIG VoiceOver: "Specify how elements are grouped,
/// ordered or linked"; HIG Lists and tables: "Provide appropriate selection feedback."
@MainActor
@Suite(.serialized)
struct CompeteYourRankAccessibilityTests {
    typealias Page = CompeteLoadingAccessibilityTests
    typealias Layout = CompeteLeaderboardsAccessibilityTests.Layout
    typealias Motion = CompeteLoadingAccessibilityTests.Motion

    /// The fixture viewer ranked 45th of 60 on every board, on none of their top rows.
    static let viewer = "fixture-riv-ranked"
    static let jumpLabel = "Your rank, 45th. Jump to your position."
    /// The fixture's top rows on every board, in order.
    static let topRows = ["fixture-player-1", "fixture-player-2", "fixture-rank-3"]
    static let rowPrefix = "fst.rankings.row."

    /// The viewer's row under a board's preview.
    static func spotlightID(_ board: String) -> String { "fst.compete.leaderboard-card.\(board).spotlight" }
    /// A board's View Full Leaderboard.
    static func viewAllID(_ board: String) -> String { "fst.compete.leaderboard-card.\(board).view-all" }

    /// Routes the page pushed.
    @MainActor final class RouteRecorder {
        var routes: [AppRoute] = []
    }

    /// One hosted Compete page for the ranked viewer.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// The page's own elements in VoiceOver's order (no containers or scroller parts).
        func content() -> [(node: MacAXNode, frame: CGRect?)] {
            Page.content(nativeHostedReachableElements(host))
        }
    }

    /// Host Compete for `fixture-riv-ranked` with Lead and Bass shown over the loopback
    /// fixture, and wait until every card holds the viewer's row and the page has settled.
    ///
    /// - Parameters:
    ///   - layout: Stacked page or the Duo inner display's panes.
    ///   - typeSize: Dynamic Type size for the page.
    ///   - motion: Fade and Reduce Motion settings.
    ///   - recorder: Records each route the page pushes.
    /// - Returns: The settled host.
    static func host(
        _ layout: Layout = .stacked, typeSize: DynamicTypeSize = .large, motion: Motion = .instant,
        recorder: RouteRecorder = RouteRecorder()
    ) async throws -> Hosted {
        let baseURL = try await RivalsMockService.shared.baseURL()
        let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
        let suiteName = "fst.tests.compete-your-rank-a11y.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        let identity: [String: String] = ["accountId": viewer, "displayName": "Fixture Viewer"]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        for key in Page.allInstrumentKeys { storage.set(Page.visibleKeys.contains(key), forKey: key) }
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        let page = NavigationStack {
            CompeteScreen(session: session)
                .navigationDestination(for: AppRoute.self) { route in
                    Text("Destination").onAppear { recorder.routes.append(route) }
                }
        }
        let size = layout.size
        let host = nativeHostedView(
            AnyView(
                Group {
                    if let device = layout.deviceLayout { page.environment(\.deviceLayout, device) } else { page }
                }
                    .environment(\.festivalFadeInEnabled, motion != .instant)
                    .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
                    .environment(\.dynamicTypeSize, typeSize)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host, timeout: .seconds(30)) {
            let tree = macAccessibilityTree(host)
            return !tree.contains { $0.identifier == Page.spinnerID }
                && Page.boards.allSatisfy { board in tree.contains { $0.identifier == spotlightID(board.id) } }
                && tree.contains { $0.role == "AXHeading" && $0.spokenName == "Rivals" }
        }
        if motion != .instant { try await Task.sleep(for: Page.entrance) }
        return Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    // MARK: - Names, roles, order and targets

    /// Each card reads its heading, its top rows (named for their players), then the
    /// viewer's one "Jump to your position" link, then View Full Leaderboard, and draws
    /// them in that order: the row sits under the last top row, spans the card like
    /// View Full Leaderboard and is at least 44 pt tall. Its own row content and chevron
    /// are not separate stops. The same holds on the Duo carousel and at AX5.
    @Test(arguments: Layout.allCases, [DynamicTypeSize.large, .accessibility5])
    func yourRankRowReadsBetweenTheTopRowsAndViewFullLeaderboard(
        _ layout: Layout, _ typeSize: DynamicTypeSize
    ) async throws {
        let context = "\(layout), \(typeSize)"
        let hosted = try await Self.host(layout, typeSize: typeSize)
        defer { hosted.close() }
        let framed = hosted.content()
        let loaded = framed.map(\.node)
        let dump = Self.dump(loaded)
        macAccessibilityDump(loaded, name: "compete-your-rank-\(layout)-\(typeSize)")

        let jumps = loaded.filter { $0.spokenName.contains("Jump to your position") }
        #expect(jumps.map(\.identifier) == Page.boards.map { Self.spotlightID($0.id) },
                "\(context): one Jump to your position per board, in board order:\n\(dump)")

        for board in Page.boards {
            let heading = try #require(loaded.firstIndex { $0.role == "AXHeading" && $0.spokenName == board.name },
                                       "\(context): \(board.name)'s heading:\n\(dump)")
            let spotlight = try #require(loaded.firstIndex { $0.identifier == Self.spotlightID(board.id) },
                                         "\(context): \(board.name)'s your-rank row:\n\(dump)")
            let viewAll = try #require(loaded.firstIndex { $0.identifier == Self.viewAllID(board.id) },
                                       "\(context): \(board.name)'s View Full Leaderboard:\n\(dump)")
            let row = loaded[spotlight]
            #expect(["AXLink", "AXButton"].contains(row.role), "\(context): the row navigates: \(row)")
            #expect(row.spokenName == Self.jumpLabel, "\(context): names its rank and destination: \(row)")

            // Heading, top rows, the viewer's row, View Full Leaderboard: nothing between.
            let between = loaded[(heading + 1)..<spotlight]
            #expect(between.map(\.identifier) == Self.topRows.map { Self.rowPrefix + $0 },
                    "\(context): \(board.name)'s top rows lead into the viewer's row:\n\(dump)")
            #expect(between.allSatisfy { ["AXLink", "AXButton"].contains($0.role) && $0.spokenName.hasPrefix("#") },
                    "\(context): top rows keep their own names:\n\(Self.dump(Array(between)))")
            #expect(between.allSatisfy { !$0.spokenName.contains("Your rank") && !$0.spokenName.contains("Jump") },
                    "\(context): only the viewer's row jumps:\n\(Self.dump(Array(between)))")
            #expect(viewAll == spotlight + 1, "\(context): View Full Leaderboard follows the viewer's row:\n\(dump)")

            let frame = try #require(framed[spotlight].frame, "\(context): \(board.name)'s row has a frame")
            let lastTop = try #require(framed[spotlight - 1].frame, "\(context): \(board.name)'s last top row")
            let action = try #require(framed[viewAll].frame, "\(context): \(board.name)'s View Full Leaderboard")
            #expect(frame.height >= Page.minimumTarget - 0.5, "\(context): a 44 pt target: \(frame)")
            #expect(frame.minY >= lastTop.maxY - 1 && frame.maxY <= action.minY + 1,
                    "\(context): drawn between the top rows and View Full Leaderboard: \(lastTop) \(frame) \(action)")
            #expect(abs(frame.minX - lastTop.minX) <= 1 && abs(frame.width - lastTop.width) <= 1,
                    "\(context): as wide as the card's rows: \(frame) vs \(lastTop)")
            if layout == .stacked {
                #expect(frame.minX >= -0.5 && frame.maxX <= hosted.host.bounds.width + 0.5,
                        "\(context): lies on the page: \(frame)")
            }
        }

        #expect(!loaded.contains { $0.identifier.hasPrefix("fst.rankings.footer-row.") },
                "\(context): the row's content reads only through its link:\n\(dump)")
        #expect(!loaded.contains { $0.identifier == Self.rowPrefix + Self.viewer },
                "\(context): the viewer is not also a top row:\n\(dump)")
        let symbolNames: Set<String> = ["chevron.forward", "Forward"]
        #expect(!loaded.contains { symbolNames.contains($0.spokenName) }, "\(context): no chevron on its own:\n\(dump)")
        #expect(loaded.allSatisfy { !$0.spokenName.isEmpty }, "\(context): nothing unnamed:\n\(dump)")
        #expect(macAccessibilityFindings(macAccessibilityTree(hosted.host)).isEmpty, "\(context)")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the row takes the stacked row layout, so it
    /// grows taller instead of clipping, keeps its name and stays a full-width target
    /// above View Full Leaderboard.
    @Test func yourRankRowStacksAtAccessibilitySizes() async throws {
        let standard = try await Self.host()
        let id = Self.spotlightID("Solo_Guitar")
        let standardFrame = try #require(nativeHostedAccessibilityFrame(id, in: standard.host))
        standard.close()

        let hosted = try await Self.host(typeSize: .accessibility5)
        defer { hosted.close() }
        let frame = try #require(nativeHostedAccessibilityFrame(id, in: hosted.host))
        let topRow = try #require(nativeHostedAccessibilityElement(in: hosted.host) {
            nativeHostedAccessibilityString($0, "accessibilityIdentifier") == Self.rowPrefix + "fixture-player-1"
        }.flatMap { nativeHostedAccessibilityFrame(of: $0, in: hosted.host) })
        let action = try #require(nativeHostedAccessibilityFrame(Self.viewAllID("Solo_Guitar"), in: hosted.host))
        // macOS text does not scale with the environment's size, so the hosted check is the
        // stacked accessibility layout; the iPhone journey checks real AX5 growth.
        #expect(frame.height > standardFrame.height + 2, "stacks at AX5: \(frame.height) vs \(standardFrame.height)")
        #expect(frame.height >= topRow.height - 1.5, "as tall as a stacked top row: \(frame) vs \(topRow)")
        #expect(abs(frame.width - standardFrame.width) <= 1, "keeps the card's width: \(frame) vs \(standardFrame)")
        #expect(frame.maxY <= action.minY + 1, "stays above View Full Leaderboard: \(frame) over \(action)")
        let node = try #require(macAccessibilityTree(hosted.host).first { $0.identifier == id && $0.isElement })
        #expect(node.spokenName == Self.jumpLabel, "\(node)")
    }

    // MARK: - Motion

    /// With fades and motion on, under system Reduce Motion and under the app's Reduce
    /// Motion, the page settles with the same named row in the same place in each card.
    @Test(arguments: Motion.allCases)
    func yourRankRowSettlesTheSameUnderEveryMotionSetting(_ motion: Motion) async throws {
        let hosted = try await Self.host(motion: motion)
        defer { hosted.close() }
        let loaded = hosted.content().map(\.node)
        let dump = Self.dump(loaded)
        for board in Page.boards {
            let spotlight = try #require(loaded.firstIndex { $0.identifier == Self.spotlightID(board.id) },
                                         "\(motion): \(board.name)'s your-rank row:\n\(dump)")
            #expect(loaded[spotlight].spokenName == Self.jumpLabel, "\(motion): \(loaded[spotlight])")
            #expect(spotlight + 1 < loaded.count && loaded[spotlight + 1].identifier == Self.viewAllID(board.id),
                    "\(motion): \(board.name)'s View Full Leaderboard follows it:\n\(dump)")
            let frame = try #require(nativeHostedAccessibilityFrame(Self.spotlightID(board.id), in: hosted.host))
            #expect(frame.height >= Page.minimumTarget - 0.5 && frame.width >= Page.minimumTarget - 0.5
                    && frame.minX >= -0.5 && frame.maxX <= hosted.host.bounds.width + 0.5,
                    "\(motion): \(board.name)'s row is a 44 pt target on the page: \(frame)")
        }
    }

    // MARK: - Activation

    /// Press an element the way VoiceOver (VO-Space), Voice Control and Switch Control do.
    ///
    /// - Parameters:
    ///   - identifier: The element's identifier (the first match).
    ///   - host: The page's hosting view.
    static func press(_ identifier: String, in host: NSView) throws {
        let control = try #require(nativeHostedAccessibilityElement(identifier, in: host), "\(identifier) to press")
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(control.responds(to: press), "\(identifier) offers a press action")
        _ = control.perform(press)
    }

    /// Pressing the viewer's row opens that card's full board (the combo's for the combo
    /// card) on page 2, where rank 45 lies with 25 rows a page, with their row to reveal.
    /// `Page.boards` ids: the Lead + Bass combo, Lead, Bass.
    @Test(arguments: ["03", "Solo_Guitar", "Solo_Bass"])
    func pressingYourRankRowOpensYourPositionOnTheFullBoard(_ board: String) async throws {
        let recorder = RouteRecorder()
        let hosted = try await Self.host(recorder: recorder)
        defer { hosted.close() }
        try Self.press(Self.spotlightID(board), in: hosted.host)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) { !recorder.routes.isEmpty }
        let route = try #require(recorder.routes.first)
        switch board {
        case "Solo_Guitar":
            #expect(route == .fullRankings(instrument: .lead, rankBy: "totalscore", page: 2, focusSelected: true))
        case "Solo_Bass":
            #expect(route == .fullRankings(instrument: .bass, rankBy: "totalscore", page: 2, focusSelected: true))
        default:
            guard case let .fullComboRankings(combo, rankBy, page, focusSelected) = route else {
                Issue.record("the combo card opens the combo board: \(route)")
                return
            }
            #expect(combo.comboId == board && rankBy == "totalscore" && page == 2 && focusSelected, "\(route)")
        }
    }

    /// A top row beside it still opens that player's profile, not a board.
    @Test func pressingATopRowStillOpensTheProfile() async throws {
        let recorder = RouteRecorder()
        let hosted = try await Self.host(recorder: recorder)
        defer { hosted.close() }
        try Self.press(Self.rowPrefix + "fixture-player-2", in: hosted.host)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) { !recorder.routes.isEmpty }
        let route = try #require(recorder.routes.first)
        guard case let .player(accountId, _) = route else {
            Issue.record("a top row opens a profile: \(route)")
            return
        }
        #expect(accountId == "fixture-player-2")
    }
}
#endif
