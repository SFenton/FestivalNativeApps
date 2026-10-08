#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Poses (issue #345)

/// The iPhone Duo poses whose chrome is the system vertical bar, with the board's
/// width beside an 84 pt trailing bar (`.agents/platforms/apple/duo.md` geometry).
enum DuoBoardPose: String, CaseIterable, CustomTestStringConvertible {
    case folded, outerLandscape, unfolded

    var testDescription: String { rawValue }

    /// The resolved layout, as `publishesDeviceLayout` would inject it.
    var layout: DeviceLayout {
        switch self {
        case .folded:
            DeviceLayout.resolve(LayoutSignals(
                size: CGSize(width: 466, height: 678), widthClass: .compact,
                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
                verticalBarEdge: .trailing, hinge: .closed
            ))
        case .outerLandscape:
            DeviceLayout.resolve(LayoutSignals(
                size: CGSize(width: 678, height: 466), widthClass: .compact, heightClass: .compact,
                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 21, trailing: 84),
                verticalBarEdge: .trailing, hinge: .closed
            ))
        case .unfolded:
            DeviceLayout.resolve(LayoutSignals(
                size: CGSize(width: 951, height: 669), widthClass: .regular,
                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 21, trailing: 71),
                verticalBarEdge: .trailing, hinge: .fullyOpen
            ))
        }
    }

    /// The board's size: the window less the vertical bar.
    var boardSize: CGSize {
        switch self {
        case .folded: CGSize(width: 382, height: 678)
        case .outerLandscape: CGSize(width: 594, height: 466)
        case .unfolded: CGSize(width: 880, height: 669)
        }
    }
}

/// The pager's five controls under `idPrefix`.
private func pagerIdentifiers(_ idPrefix: String) -> [String] {
    ["first", "previous", "info", "next", "last"].map { "\(idPrefix).page-\($0)" }
}

/// Every pager control's frame, or nil until all of them are realized.
@MainActor
private func pagerFrames(_ idPrefix: String, in host: NSView) -> [CGRect]? {
    let frames = pagerIdentifiers(idPrefix).compactMap { nativeHostedAccessibilityFrame($0, in: host) }
    return frames.count == 5 ? frames : nil
}

/// Assert the in-content pager sits at the bottom of the board, inside it, and (where
/// a vertical hinge crosses the board) wholly on the screen beside the vertical bar.
@MainActor
private func expectInContentPager(
    _ frames: [CGRect], board: CGSize, layout: DeviceLayout, pose: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let span = frames.reduce(frames[0]) { $0.union($1) }
    #expect(span.minX >= 0 && span.maxX <= board.width, "\(pose): pager \(span) leaves the board",
            sourceLocation: sourceLocation)
    #expect(span.maxY <= board.height && span.minY > board.height * 0.6,
            "\(pose): pager \(span) is not under the board", sourceLocation: sourceLocation)
    for frame in frames {
        #expect(frame.width >= 44 && frame.height >= 44, "\(pose): \(frame) under 44 pt",
                sourceLocation: sourceLocation)
    }
    if let hinge = layout.screenDivide(), hinge.minX < board.width {
        #expect(span.minX >= hinge.maxX, "\(pose): pager \(span) is not beside the bar (divide \(hinge))",
                sourceLocation: sourceLocation)
    }
}

// MARK: - Band Rankings

/// Band Rankings keeps its in-content pager (its own `RankingsFloatingBar`) in every
/// vertical-bar pose, never rail items; unfolded, on the screen beside the bar (#345).
@MainActor
@Test(.serialized, arguments: DuoBoardPose.allCases)
func bandRankingsKeepsTheInContentPagerOnDuo(pose: DuoBoardPose) async throws {
    let layout = pose.layout
    #expect(layout.sectionChrome == .verticalBar(.trailing))
    nativeHostedEnableAccessibility()
    let transport = HostedRankingsTransport()
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    let session = FestivalSession(factory: { client })
    let defaults = try #require(UserDefaults(suiteName: "fst.tests.duo-board-pager.\(UUID().uuidString)"))
    defaults.set(true, forKey: "fst.accessibility.reduceMotion")
    let size = pose.boardSize
    let host = nativeHostedView(
        NavigationStack { BandRankingsScreen(session: session, bandType: "Band_Duets") }
            .environment(\.deviceLayout, layout)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .defaultAppStorage(defaults),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        nativeHostedAccessibility(host).contains("Member 1A") && pagerFrames("fst.band-rankings", in: host) != nil
    }
    _ = try nativeHostedPNG(
        image, filename: "band-rankings-duo-\(pose.rawValue).png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    let frames = try #require(pagerFrames("fst.band-rankings", in: host), "\(pose): no in-content pager")
    expectInContentPager(frames, board: size, layout: layout, pose: pose.rawValue)
}

// MARK: - Song leaderboard

/// Where the full song board is shown.
enum SongBoardPlacement: String, CaseIterable, CustomTestStringConvertible {
    /// A split's trailing pane beside Song Detail (iPad/Mac width).
    case splitTrailing
    /// Pushed full width on each vertical-bar Duo pose.
    case duoFolded, duoOuterLandscape, duoUnfolded

    var testDescription: String { rawValue }

    var layout: DeviceLayout {
        switch self {
        case .splitTrailing: .standardPhone
        case .duoFolded: DuoBoardPose.folded.layout
        case .duoOuterLandscape: DuoBoardPose.outerLandscape.layout
        case .duoUnfolded: DuoBoardPose.unfolded.layout
        }
    }

    var size: CGSize {
        switch self {
        case .splitTrailing: CGSize(width: 520, height: 900)
        case .duoFolded: DuoBoardPose.folded.boardSize
        case .duoOuterLandscape: DuoBoardPose.outerLandscape.boardSize
        case .duoUnfolded: DuoBoardPose.unfolded.boardSize
        }
    }
}

/// The full song board keeps its pager under the board, with the selected player's
/// row pinned directly above it, in a split's trailing pane and on every vertical-bar
/// Duo pose (#345; leaderboard-row R5).
@MainActor
@Test(.serialized, arguments: SongBoardPlacement.allCases)
func songBoardKeepsThePagerUnderTheBoard(placement: SongBoardPlacement) async throws {
    nativeHostedEnableAccessibility()
    let session = try await spotlightSelectedSession()
    let song = try spotlightFixtureSong()
    // The selected player (rank 57) is off this page, so the pinned footer shows.
    let payload = try spotlightFixtureLeaderboard(spotlightRank: nil)
    let size = placement.size
    let context: SplitPaneContext? = placement == .splitTrailing
        ? SplitPaneContext(paneWidth: size.width, role: .trailing, besideList: .songDetail) : nil
    let host = nativeHostedView(
        NavigationStack {
            SoloLeaderboardScreen(
                song: song, instrument: .lead, session: session,
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            )
            .splitPaneContext(context)
        }
        .environment(\.deviceLayout, placement.layout)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        nativeHostedAccessibilityFrame("fst.song-leaderboard.spotlight-footer", in: host) != nil
            && pagerFrames("fst.song-leaderboard", in: host) != nil
    }
    _ = try nativeHostedPNG(
        image, filename: "song-leaderboard-pager-\(placement.rawValue).png",
        environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    let frames = try #require(pagerFrames("fst.song-leaderboard", in: host), "\(placement): no pager")
    expectInContentPager(frames, board: size, layout: placement.layout, pose: placement.rawValue)
    let footer = try #require(nativeHostedAccessibilityFrame("fst.song-leaderboard.spotlight-footer", in: host))
    let pagerTop = frames.map(\.minY).min() ?? 0
    #expect(footer.maxY <= pagerTop, "\(placement): footer \(footer) is not pinned above the pager at \(pagerTop)")
    #expect(pagerTop - footer.maxY <= 24, "\(placement): footer \(footer) drifted from the pager at \(pagerTop)")
}
#endif
