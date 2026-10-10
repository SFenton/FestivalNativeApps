#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Song band leaderboard footer accessibility (issue #306, backfilled by #461)

/// The full Duos/Trios/Quads board pins the selected player's band above the pager
/// (issue #306: the shared ``SelectedScoreFooterRow`` over ``PinnedFooterBacking``, whose
/// action follows the Solo footer, #307). These hosted checks pin what that row exposes
/// on every Apple platform (the same SwiftUI runs on iPhone, iPad, iPhone Duo and Mac):
/// one named button or link per action, reading order between the rows and the pager,
/// a full-size target, the accessibility-size layout, activation of both actions (Jump
/// shows the band's page, Open band pushes Band Detail) and the opaque backing under the
/// system's and the app's transparency and contrast settings.
///
/// Activation goes through the control's AXPress action, which VoiceOver, Voice Control
/// and Switch Control send. A hosted test cannot give a SwiftUI button keyboard focus:
/// SwiftUI reads the Mac's Keyboard navigation setting outside the process (forcing
/// `NSApplication.isFullKeyboardAccessEnabled` on changed nothing, #461), and agents must
/// not change that system setting. The footer's Tab focus ring and Return come from the
/// shared row style through `pinnedFooterControl`, which `tools/pattern_guard.py`
/// (`leaderboard-row/apple-pinned-footer-control`) keeps on every board.
///
/// HIG Accessibility: "Provide alternative text labels for all important interface
/// elements"; iOS/iPadOS default control size 44×44 pt; "If the default does not meet
/// these minimums, provide a higher-contrast scheme when Increase Contrast is on." HIG
/// Typography: "Keep text truncation to a minimum as font size increases."
@MainActor
@Suite(.serialized)
struct SongBandFooterAccessibilityTests {
    // MARK: - Fixture

    static let footerID = "fst.song-band-leaderboard.spotlight-footer"
    static let jumpID = "fst.song-band-leaderboard.spotlight-jump"
    static let openID = "fst.song-band-leaderboard.spotlight-open"
    static let rowPrefix = "fst.song-band-leaderboard.row."
    static let pagerIDs = ["first", "previous", "next", "last"].map { "fst.song-band-leaderboard.page-\($0)" }
        + ["fst.song-band-leaderboard.page-info"]
    /// The mock's `fixture-pulse` Duos board: `fixture-player-1`'s band is rank 29 on page 2.
    static let jumpLabel = "Your band's rank, 29th. Jump to your band's position."
    static let openLabel = "Your band's rank, 29th. Open band."
    static let size = CGSize(width: 402, height: 900)

    /// Routes the board pushed (Open band's Band Detail).
    @MainActor final class RouteRecorder {
        var routes: [AppRoute] = []
    }

    /// One hosted band board over the keyless fixture service.
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

    /// Host the `fixture-pulse` Duos board at a phone width with `fixture-player-1`
    /// selected, and wait for the footer's action.
    ///
    /// - Parameters:
    ///   - page: The page to open: 1 jumps to the band's page, 2 holds its row.
    ///   - typeSize: Dynamic Type size for the whole page.
    ///   - recorder: Records each route the stack pushes.
    /// - Returns: The settled host, its window and storage.
    /// - Throws: An unavailable fixture service, catalogue song or capture.
    static func hostBoard(
        page: Int, typeSize: DynamicTypeSize = .large, recorder: RouteRecorder = RouteRecorder()
    ) async throws -> Hosted {
        let client = try FestivalAPI(
            baseURL: try await RivalsMockService.shared.baseURL(), transport: URLSessionHTTPTransport()
        )
        let suiteName = "fst-band-footer-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let identity = ["accountId": "fixture-player-1", "displayName": "Fixture Player 1"]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets", initialPage: page)
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
        let action = page == 1 ? jumpID : openID
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityFrame(action, in: host) != nil
                && nativeHostedAccessibilityFrame("fst.song-band-leaderboard.page-info", in: host) != nil
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

    /// Off its page the footer is one button that names the band's rank and the jump; on
    /// its page it is one link (or button) that names Open band. The row's chevron and
    /// symbols stay out of the tree, and nothing in the page is unnamed.
    @Test(arguments: [1, 2])
    func footerIsOneNamedControlForItsAction(page: Int) async throws {
        let hosted = try await Self.hostBoard(page: page)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "song-band-footer-page-\(page)")
        let (id, label, other) = page == 1
            ? (Self.jumpID, Self.jumpLabel, Self.openID)
            : (Self.openID, Self.openLabel, Self.jumpID)
        let control = try Self.element(id, in: nodes)
        if page == 1 {
            #expect(control.role == "AXButton", "the jump is a button: \(control)")
        } else {
            #expect(["AXLink", "AXButton"].contains(control.role), "Open band navigates: \(control)")
        }
        #expect(control.spokenName == label, "\(control)")
        #expect(!nodes.contains { $0.identifier == other && $0.isElement }, "one action at a time")
        #expect(nodes.contains { $0.identifier == Self.footerID }, "footer container")
        let symbolNames: Set<String> = ["chevron.forward", "Forward", "star.fill", "Star"]
        #expect(!nodes.contains { $0.isElement && symbolNames.contains($0.spokenName) },
                "no chevron or symbol exposed on its own")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Reading order and target size

    /// Band rows read before the footer and the footer before the pager, matching the
    /// layout: the footer rests above the pager, spans the page inside its margins and
    /// is at least a 44 pt target.
    @Test func footerReadsBetweenRowsAndPagerWithAFullSizeTarget() async throws {
        let hosted = try await Self.hostBoard(page: 1)
        defer { hosted.close() }
        let host = hosted.host
        let tree = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(tree, name: "song-band-footer-order")
        let order = tree.filter(\.isElement)
        let heading = try #require(order.firstIndex { $0.role == "AXHeading" }, "the board's header in the reading order")
        let rows = order.indices.filter { order[$0].identifier.hasPrefix(Self.rowPrefix) }
        let footer = try #require(order.firstIndex { $0.identifier == Self.jumpID }, "footer in the reading order")
        let pager = Self.pagerIDs.compactMap { id in order.firstIndex { $0.identifier == id } }
        #expect(!rows.isEmpty, "band rows in the reading order")
        #expect(rows.allSatisfy { $0 > heading }, "the header reads before the rows: \(heading) vs \(rows)")
        #expect(pager.count == Self.pagerIDs.count, "every pager control in the reading order: \(pager)")
        #expect(rows.allSatisfy { $0 < footer }, "rows read before the footer: \(rows) vs \(footer)")
        #expect(pager.allSatisfy { $0 > footer }, "the pager reads after the footer: \(pager) vs \(footer)")

        let frame = try #require(nativeHostedAccessibilityFrame(Self.jumpID, in: host))
        let info = try #require(nativeHostedAccessibilityFrame("fst.song-band-leaderboard.page-info", in: host))
        #expect(frame.height >= 44 - 0.5, "the footer is a 44 pt target: \(frame)")
        #expect(frame.width >= Self.size.width - 32 - 1, "the footer spans the page inside its margins: \(frame)")
        #expect(frame.maxY <= info.minY + 0.5, "the footer rests above the pager: \(frame) over \(info)")
        #expect(frame.minY >= 0 && info.maxY <= Self.size.height + 0.5, "both stay on screen")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the footer grows instead of clipping, keeps its
    /// label and stays on screen above a reachable pager whose controls keep 44 pt.
    @Test func footerGrowsAndKeepsThePagerReachableAtAccessibilitySizes() async throws {
        let standard = try await Self.hostBoard(page: 1)
        let standardHeight = try #require(nativeHostedAccessibilityFrame(Self.jumpID, in: standard.host)).height
        standard.close()

        let hosted = try await Self.hostBoard(page: 1, typeSize: .accessibility5)
        defer { hosted.close() }
        let host = hosted.host
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "song-band-footer-ax5")
        #expect(try Self.element(Self.jumpID, in: nodes).spokenName == Self.jumpLabel)
        let frame = try #require(nativeHostedAccessibilityFrame(Self.jumpID, in: host))
        #expect(frame.height > standardHeight + 10, "the footer grows at AX5: \(frame.height) vs \(standardHeight)")
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

    /// Activating Jump off the band's page shows page 2 with the band's own row, where the
    /// same footer becomes the Open band link with its label (issue #307's jump-or-open
    /// rule).
    @Test func jumpActivationShowsTheBandsPageAndTurnsTheFooterIntoOpen() async throws {
        let hosted = try await Self.hostBoard(page: 1)
        defer { hosted.close() }
        let host = hosted.host
        let bandRowID = Self.rowPrefix + "fixture-band-fixture-player-1:29"
        #expect(!macAccessibilityTree(host).contains { $0.identifier == bandRowID }, "page 1 holds ranks 1–25")
        try Self.press(Self.jumpID, in: host)
        try await nativeHostedSettle(host, timeout: .seconds(30)) {
            nativeHostedAccessibilityFrame(Self.openID, in: host) != nil
        }
        let nodes = macAccessibilityTree(host)
        let bandRow = try Self.element(bandRowID, in: nodes)
        #expect(bandRow.spokenName.hasPrefix("Your band, Rank 29"), "the jump shows the band's own row: \(bandRow)")
        #expect(try Self.element(Self.openID, in: nodes).spokenName == Self.openLabel)
        #expect(!nodes.contains { $0.identifier == Self.jumpID && $0.isElement }, "one action at a time")
    }

    /// Activating Open band on the band's page pushes that band's Band Detail.
    @Test func openActivationPushesBandDetail() async throws {
        let recorder = RouteRecorder()
        let hosted = try await Self.hostBoard(page: 2, recorder: recorder)
        defer { hosted.close() }
        try Self.press(Self.openID, in: hosted.host)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) { !recorder.routes.isEmpty }
        let route = try #require(recorder.routes.first, "Open band pushed nothing")
        guard case let .band(_, name, bandType, teamKey) = route else {
            Issue.record("Open band pushed \(route), not Band Detail")
            return
        }
        #expect(bandType == "Band_Duets")
        #expect(teamKey?.isEmpty == false, "the band's team key travels with the route")
        #expect(name?.contains("Fixture Player 1") == true, "the selected player's band: \(name ?? "nil")")
    }

    // MARK: - Transparency and contrast

    /// Settings the footer's backing must follow, like the pager beside it.
    enum Surface: String, CaseIterable, CustomTestStringConvertible {
        case standard, systemReduceTransparency, systemIncreaseContrast, lessTransparency, moreContrast

        var testDescription: String { rawValue }
    }

    /// The footer row's surface pixel (RGB 0–255) over a solid backdrop, between the
    /// card's rim and its rank.
    ///
    /// - Parameters:
    ///   - surface: Accessibility setting under test.
    ///   - backdrop: Solid colour behind the footer.
    /// - Returns: The sampled pixel.
    static func footerSurface(_ surface: Surface, backdrop: Color) throws -> (Int, Int, Int) {
        let suite = "fst.tests.band-footer-surface.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(surface == .lessTransparency, forKey: "fst.accessibility.lessTransparency")
        defaults.set(surface == .moreContrast, forKey: "fst.accessibility.moreContrast")
        let entry = LeaderboardEntry(
            accountId: "band-fixture", displayName: "Fixture Player 1 + Fixture Player 2",
            score: 308_610, rank: 29, localRank: nil, accuracy: 995_000, isFullCombo: false,
            stars: 5, season: nil, difficulty: nil
        )
        let size = CGSize(width: 402, height: 80)
        let content = ZStack {
            backdrop
            SelectedScoreFooterRow(entry: entry, currentSeason: nil, starsAfterScore: true)
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
        // 6 pt inside the card's leading edge (past its 1 pt rim, before the 14 pt
        // padding that holds the rank), at mid-height; CGContext rows run bottom-up.
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
    /// Contrast it sits on an opaque backing, so its text no longer depends on the
    /// artwork or rows behind it (surface-materials R4; the app's toggles were ignored
    /// before #461).
    @Test(arguments: Surface.allCases)
    func footerBackingTurnsOpaqueUnderTransparencyAndContrastSettings(surface: Surface) throws {
        let warm = try Self.footerSurface(surface, backdrop: Color(red: 0.85, green: 0.3, blue: 0.2))
        let cool = try Self.footerSurface(surface, backdrop: Color(red: 0.2, green: 0.5, blue: 0.9))
        if surface == .standard {
            #expect(Self.distance(warm, cool) > 20, "the standard footer is translucent: \(warm) vs \(cool)")
        } else {
            #expect(Self.distance(warm, cool) <= 3, "\(surface): the footer is opaque: \(warm) vs \(cool)")
        }
        #expect(PinnedFooterBacking.isOpaque(
            reduceTransparency: surface == .systemReduceTransparency,
            systemContrast: surface == .systemIncreaseContrast ? .increased : .standard,
            lessTransparency: surface == .lessTransparency, moreContrast: surface == .moreContrast
        ) == (surface != .standard))
    }
}
#endif
