#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Full Rankings footer accessibility (issue #466, for #318)

/// Full Rankings pins the selected player's own row above the pager on every page,
/// their own page included (issue #318: ``RankingSpotlight/pinnedFooter``; off their
/// page it is a Jump button, on it an Open your statistics link, leaderboard-row R5/R7).
/// These hosted checks pin what that footer exposes on every Apple platform (the same
/// SwiftUI runs on iPhone, iPad, iPhone Duo and Mac), in the state #318 added above all:
/// one named control per action, reading order heading → rows (the player's own row
/// among them) → footer → pager, a full-size target resting above the pager, the
/// accessibility-size layout, AXPress activation of both actions and the opaque backing
/// under the system's and the app's transparency and contrast settings. The off-page
/// reading order is also held by `BoardBottomChromeReadingOrderTests`; the iPhone AX5
/// journey and system audit are `FullRankingsFooterJourneyTests`.
///
/// Activation goes through AXPress (VoiceOver, Voice Control and Switch Control): a hosted
/// test cannot give a SwiftUI button keyboard focus (#461). The footer's Tab focus ring and
/// Return come from `pinnedFooterControl`, which `tools/pattern_guard.py`
/// (`leaderboard-row/apple-pinned-footer-control`) keeps on every board.
///
/// HIG Accessibility: iOS/iPadOS default control size 44×44 pt. HIG VoiceOver: "Specify how
/// elements are grouped, ordered or linked where relationships are only visual." HIG
/// Typography: "Keep text truncation to a minimum as font size increases."
@MainActor
@Suite(.serialized)
struct FullRankingsFooterAccessibilityTests {
    // MARK: - Fixture

    static let footerID = "fst.full-rankings.spotlight-footer"
    static let jumpID = "fst.full-rankings.spotlight-jump"
    static let openID = "fst.full-rankings.spotlight-open"
    static let rowPrefix = "fst.rankings.row."
    /// The selected player's own row on their page.
    static let ownRowID = "fst.rankings.row.\(LongRankingsTransport.selectedAccount)"
    static let pagerIDs = ["first", "previous", "info", "next", "last"].map { "fst.full-rankings.page-\($0)" }
    /// `LongRankingsTransport`: the selected player is rank 45 of 60, on page 2 of 3.
    static let jumpLabel = "Your rank, 45th. Jump to your position."
    static let openLabel = "Your rank, 45th. Open your statistics."
    static let ownRowLabel = "Your rank, 45th. Reveal Player."
    static let size = CGSize(width: 402, height: 900)

    /// Routes the board pushed (Open your statistics).
    @MainActor final class RouteRecorder {
        var routes: [AppRoute] = []
    }

    /// One hosted Full Rankings board over the keyless fixture transport.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }
    }

    /// Host Lead Full Rankings at a phone width with the fixture's player selected, and
    /// wait for the footer's action and the pager.
    ///
    /// - Parameters:
    ///   - page: The page to open: 1 jumps to the player's page, 2 holds their row.
    ///   - typeSize: Dynamic Type size for the whole page.
    ///   - recorder: Records each route the stack pushes.
    /// - Returns: The settled host, its window and storage.
    /// - Throws: An invalid fixture identity or a board that never settles.
    static func hostBoard(
        page: Int, typeSize: DynamicTypeSize = .large, recorder: RouteRecorder = RouteRecorder()
    ) async throws -> Hosted {
        let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongRankingsTransport())
        let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
        {"accountId":"\(LongRankingsTransport.selectedAccount)","displayName":"Reveal Player"}
        """.utf8))
        let session = FestivalSession(
            factory: { client }, debugSelectedPlayer: try SelectedPlayerIdentity(searchResult: result)
        )
        let suiteName = "fst-full-rankings-footer-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore", page: page)
                        .navigationDestination(for: AppRoute.self) { route in
                            Text("Destination").onAppear { recorder.routes.append(route) }
                        }
                }
                .frame(width: size.width, height: size.height)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let action = page == 2 ? openID : jumpID
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityFrame(action, in: host) != nil
                && nativeHostedAccessibilityFrame("fst.full-rankings.page-info", in: host) != nil
                && macAccessibilityTree(host).contains { $0.identifier.hasPrefix(rowPrefix) && $0.isElement }
        }
        return Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
    }

    /// The node with `identifier` that assistive technologies reach.
    static func element(_ identifier: String, in nodes: [MacAXNode]) throws -> MacAXNode {
        try #require(
            nodes.first { $0.identifier == identifier && $0.isElement },
            "\(identifier) in\n\(nodes.map(\.description).joined(separator: "\n"))"
        )
    }

    // MARK: - Names, roles and state

    /// Off the player's page the footer is one button naming their rank and the jump; on
    /// their page (#318) it stays, as one link (or button) naming Open your statistics,
    /// while the page's own row keeps its "Your rank" name. The row's chevron stays out
    /// of the tree, and nothing on the page is unnamed.
    @Test(arguments: [1, 2])
    func footerIsOneNamedControlForItsAction(page: Int) async throws {
        let hosted = try await Self.hostBoard(page: page)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "full-rankings-footer-page-\(page)")
        let (id, label, other) = page == 1
            ? (Self.jumpID, Self.jumpLabel, Self.openID)
            : (Self.openID, Self.openLabel, Self.jumpID)
        let control = try Self.element(id, in: nodes)
        if page == 1 {
            #expect(control.role == "AXButton", "the jump is a button: \(control)")
            #expect(!nodes.contains { $0.identifier == Self.ownRowID }, "page 1 holds ranks 1–25")
        } else {
            #expect(["AXLink", "AXButton"].contains(control.role), "Open your statistics navigates: \(control)")
            let ownRow = try Self.element(Self.ownRowID, in: nodes)
            #expect(ownRow.spokenName == Self.ownRowLabel, "the page's own row: \(ownRow)")
        }
        #expect(control.spokenName == label, "\(control)")
        #expect(!nodes.contains { $0.identifier == other && $0.isElement }, "one action at a time")
        #expect(nodes.contains { $0.identifier == Self.footerID }, "footer container")
        #expect(!nodes.contains { $0.identifier.hasPrefix("fst.rankings.footer-row.") && $0.isElement },
                "the footer's row reads only through its control")
        let symbolNames: Set<String> = ["chevron.forward", "Forward"]
        #expect(!nodes.contains { $0.isElement && symbolNames.contains($0.spokenName) },
                "no chevron exposed on its own")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Reading order and target size

    /// On the player's own page the heading reads first, then the rows (their own row
    /// among them), then the pinned footer, then the pager left to right, matching the
    /// layout: the footer rests above the pager, spans the page inside its margins and
    /// is at least a 44 pt target.
    @Test func footerOnThePlayersPageReadsBetweenRowsAndPagerWithAFullSizeTarget() async throws {
        let hosted = try await Self.hostBoard(page: 2)
        defer { hosted.close() }
        let host = hosted.host
        let tree = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(tree, name: "full-rankings-footer-order")
        let order = tree.filter(\.isElement)
        let heading = try #require(order.firstIndex { $0.role == "AXHeading" }, "the board's title in the reading order")
        let rows = order.indices.filter { order[$0].identifier.hasPrefix(Self.rowPrefix) }
        let ownRow = try #require(order.firstIndex { $0.identifier == Self.ownRowID }, "own row in the reading order")
        let footer = try #require(order.firstIndex { $0.identifier == Self.openID }, "footer in the reading order")
        let pager = Self.pagerIDs.compactMap { id in order.firstIndex { $0.identifier == id } }
        #expect(!rows.isEmpty, "rows in the reading order")
        #expect(rows.allSatisfy { $0 > heading }, "the title reads before the rows: \(heading) vs \(rows)")
        #expect(rows.contains(ownRow), "the player's own row reads among the rows")
        #expect(rows.allSatisfy { $0 < footer }, "rows read before the footer: \(rows) vs \(footer)")
        #expect(pager.count == Self.pagerIDs.count, "every pager control in the reading order: \(pager)")
        #expect(pager.allSatisfy { $0 > footer }, "the pager reads after the footer: \(pager) vs \(footer)")
        #expect(pager == pager.sorted(), "the pager reads left to right: \(pager)")

        let frame = try #require(nativeHostedAccessibilityFrame(Self.openID, in: host))
        let info = try #require(nativeHostedAccessibilityFrame("fst.full-rankings.page-info", in: host))
        #expect(frame.height >= 44 - 0.5, "the footer is a 44 pt target: \(frame)")
        #expect(frame.width >= Self.size.width - 32 - 1, "the footer spans the page inside its margins: \(frame)")
        #expect(frame.maxY <= info.minY + 0.5, "the footer rests above the pager: \(frame) over \(info)")
        #expect(frame.minY >= 0 && info.maxY <= Self.size.height + 0.5, "both stay on screen")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the footer on the player's page takes the stacked
    /// row layout, as tall as the page's own row (not clipped by the pinned chrome), keeps
    /// its label and stays on screen above a reachable pager whose controls keep 44 pt.
    @Test func footerGrowsAndKeepsThePagerReachableAtAccessibilitySizes() async throws {
        let standard = try await Self.hostBoard(page: 2)
        let standardHeight = try #require(nativeHostedAccessibilityFrame(Self.openID, in: standard.host)).height
        standard.close()

        let hosted = try await Self.hostBoard(page: 2, typeSize: .accessibility5)
        defer { hosted.close() }
        let host = hosted.host
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "full-rankings-footer-ax5")
        #expect(try Self.element(Self.openID, in: nodes).spokenName == Self.openLabel)
        let frame = try #require(nativeHostedAccessibilityFrame(Self.openID, in: host))
        let ownRow = try #require(nativeHostedAccessibilityFrame(Self.ownRowID, in: host))
        // macOS text does not scale with the environment's size, so the hosted check is the
        // stacked accessibility layout; the iPhone journey checks real AX5 growth.
        #expect(frame.height > standardHeight + 2, "the footer stacks at AX5: \(frame.height) vs \(standardHeight)")
        #expect(frame.height >= ownRow.height - 1.5,
                "the pinned footer is not clipped below the page's own row: \(frame) vs \(ownRow)")
        #expect(frame.minY >= 0, "the footer stays on screen: \(frame)")
        for id in Self.pagerIDs {
            let control = try #require(nativeHostedAccessibilityFrame(id, in: host), "\(id) at AX5")
            #expect(control.minY >= frame.maxY - 0.5, "\(id) stays below the footer: \(control) under \(frame)")
            #expect(control.maxY <= Self.size.height + 0.5, "\(id) stays on screen: \(control)")
            #expect(control.height >= 44 - 0.5, "\(id) keeps a 44 pt target: \(control)")
        }
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Activation

    /// Press a control the way VoiceOver (VO-Space), Voice Control and Switch Control do:
    /// its AXPress action.
    ///
    /// - Parameters:
    ///   - identifier: The control's identifier.
    ///   - host: The board's hosting view.
    /// - Throws: A missing control or one without a press action.
    static func press(_ identifier: String, in host: NSView) throws {
        let control = try #require(nativeHostedAccessibilityElement(identifier, in: host), "\(identifier) to press")
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(control.responds(to: press), "\(identifier) offers a press action")
        _ = control.perform(press)
    }

    /// Activating Jump off the player's page shows page 2 with their own row, where the
    /// footer stays pinned and becomes Open your statistics (issue #318: before it, the
    /// footer vanished on this page).
    @Test func jumpActivationShowsThePlayersPageAndKeepsTheFooterAsOpen() async throws {
        let hosted = try await Self.hostBoard(page: 1)
        defer { hosted.close() }
        let host = hosted.host
        try Self.press(Self.jumpID, in: host)
        try await nativeHostedSettle(host, timeout: .seconds(30)) {
            nativeHostedAccessibilityFrame(Self.openID, in: host) != nil
                && nativeHostedAccessibilityFrame(Self.ownRowID, in: host) != nil
        }
        let nodes = macAccessibilityTree(host)
        #expect(try Self.element(Self.ownRowID, in: nodes).spokenName == Self.ownRowLabel)
        #expect(try Self.element(Self.openID, in: nodes).spokenName == Self.openLabel)
        #expect(!nodes.contains { $0.identifier == Self.jumpID && $0.isElement }, "one action at a time")
        // An adjustable element on macOS (AXUnknown) reports its value as the value
        // description, which VoiceOver reads (as in SoloLeaderboardPagingAccessibilityTests).
        let info = try Self.element("fst.full-rankings.page-info", in: nodes)
        let value = info.value.isEmpty
            ? nativeHostedAccessibilityElement(info.identifier, in: host)?
                .value(forKey: "accessibilityValueDescription") as? String ?? ""
            : info.value
        #expect(value == "2 of 3", "the pager reads the player's page: '\(value)'")
    }

    /// Activating Open your statistics on the player's page pushes Statistics.
    @Test func openActivationPushesStatistics() async throws {
        let recorder = RouteRecorder()
        let hosted = try await Self.hostBoard(page: 2, recorder: recorder)
        defer { hosted.close() }
        try Self.press(Self.openID, in: hosted.host)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) { !recorder.routes.isEmpty }
        #expect(recorder.routes.first == .statistics, "Open pushed \(recorder.routes)")
    }

    // MARK: - Transparency and contrast

    /// Settings the footer's backing must follow, like the pager beside it.
    enum Surface: String, CaseIterable, CustomTestStringConvertible {
        case standard, systemReduceTransparency, systemIncreaseContrast, lessTransparency, moreContrast

        var testDescription: String { rawValue }
    }

    /// The Full Rankings footer row's surface pixel (RGB 0–255) over a solid backdrop,
    /// between the card's rim and its rank, drawn as `selectedRowFooter` draws it.
    ///
    /// - Parameters:
    ///   - surface: Accessibility setting under test.
    ///   - backdrop: Solid colour behind the footer.
    /// - Returns: The sampled pixel.
    static func footerSurface(_ surface: Surface, backdrop: Color) throws -> (Int, Int, Int) {
        let suite = "fst.tests.full-rankings-footer-surface.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(surface == .lessTransparency, forKey: "fst.accessibility.lessTransparency")
        defaults.set(surface == .moreContrast, forKey: "fst.accessibility.moreContrast")
        let entry = try LongRankingsTransport.selectedEntry()
        let size = CGSize(width: 402, height: 80)
        let content = ZStack {
            backdrop
            AccountRankingRow(entry: entry, metric: .totalscore, isSelected: true, cardSurface: true, opensProfile: false)
                .modifier(PinnedFooterBacking())
                .padding(.horizontal, 16)
        }
        .environment(\._accessibilityReduceTransparency, surface == .systemReduceTransparency)
        .environment(\._colorSchemeContrast, surface == .systemIncreaseContrast ? .increased : .standard)
        .defaultAppStorage(defaults)
        .preferredColorScheme(.dark)
        // The standard translucent purple must render for real.
        let host = nativeHostedView(content, size: size, forceGlassFallback: false)
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let image = try nativeHostedImage(host)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / size.width
        // 6 pt inside the card's leading edge (past its rim, before the row's padding that
        // holds the rank), at mid-height; CGContext rows run bottom-up.
        let x = Int(((16 + 6) * scale).rounded())
        let y = height - 1 - Int((size.height / 2 * scale).rounded())
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }

    /// Largest per-channel difference between two pixels.
    static func distance(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
        max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
    }

    /// Normally the selected purple lets the page behind it show through (web
    /// `purpleHighlight`); under system or in-app Reduce Transparency and Increase
    /// Contrast it sits on an opaque backing, so the pinned row's text no longer depends
    /// on the rows scrolling behind it (surface-materials R4).
    @Test(arguments: Surface.allCases)
    func footerBackingTurnsOpaqueUnderTransparencyAndContrastSettings(surface: Surface) throws {
        let warm = try Self.footerSurface(surface, backdrop: Color(red: 0.85, green: 0.3, blue: 0.2))
        let cool = try Self.footerSurface(surface, backdrop: Color(red: 0.2, green: 0.5, blue: 0.9))
        if surface == .standard {
            #expect(Self.distance(warm, cool) > 20, "the standard footer is translucent: \(warm) vs \(cool)")
        } else {
            #expect(Self.distance(warm, cool) <= 3, "\(surface): the footer is opaque: \(warm) vs \(cool)")
        }
    }
}
#endif
