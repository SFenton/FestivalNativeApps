#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// Issue #386 (accessibility tests for #327): the full band board opened for one band
// (Song Detail's selected band row, `SongBandRowFocus`) waits for its reload gate to grow
// the scroll content before it scrolls the band's row into view (load-transition R5;
// instant under Reduce Motion, R6). These tests host the real `SongBandLeaderboardScreen`
// against a fixture board and check what VoiceOver and the pointer get from that reveal:
// the spinner's spoken label while the board loads and its removal after, the revealed
// row's button role, "Your band" state, frame and reading order, and its growth at
// accessibility text sizes. `SelectedRowRevealHostedTests` covers the fade and scroll
// themselves; the iPhone journey is `SongBandRevealAccessibilityJourneyTests`.

// MARK: - Fixture

/// The 60-band fixture board (``LongBandBoardsTransport``), with every band-board read
/// held until the test releases it, so the loading state is observed by condition rather
/// than by catching a 400 ms spinner hold.
private actor HeldBandBoardTransport: HTTPTransport {
    private let base = LongBandBoardsTransport()
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Let held and later band-board reads answer.
    func release() {
        released = true
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let parts = request.url?.pathComponents ?? []
        if !released, parts.count == 6, parts[2] == "leaderboard", parts[4] == "bands" {
            await withCheckedContinuation { waiters.append($0) }
        }
        return try await base.send(request)
    }
}

/// Test IDs and labels on the hosted band board.
private enum BandRevealID {
    static let header = "fst.song-band-leaderboard.header"
    static let spinner = "fst.song-band-leaderboard.loading"
    static let rowPrefix = "fst.song-band-leaderboard.row."
    static let pagerPrefix = "fst.song-band-leaderboard.page-"
    /// The focused band: rank 20, far below the first screen.
    static let focusedRank = 20
    static let focused = "\(rowPrefix)fade-band-\(focusedRank):\(focusedRank)"

    /// The rank in a row identifier (`…row.<bandId>:<rank>`), or nil for another element.
    static func rank(_ identifier: String) -> Int? {
        guard identifier.hasPrefix(rowPrefix) else { return nil }
        return identifier.split(separator: ":").last.flatMap { Int($0) }
    }
}

/// The motion setting a hosted reveal runs with.
enum BandRevealMotion: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case standard, reduceMotion

    var testDescription: String { rawValue }
}

/// Read one accessibility attribute through selector-checked KVC (SwiftUI's AppKit
/// nodes implement `NSAccessibility` informally).
@MainActor
private func bandRevealAttribute(_ object: NSObject, _ key: String) -> Any? {
    object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
}

/// Host the real band board opened for the rank-20 band.
///
/// - Parameters:
///   - transport: The held fixture transport.
///   - reduceMotion: Whether the system Reduce Motion is on.
///   - typeSize: The Dynamic Type size to render with.
///   - size: The host's size.
/// - Returns: The hosting view and its window.
@MainActor
private func hostBandBoard(
    _ transport: HeldBandBoardTransport, reduceMotion: Bool, typeSize: DynamicTypeSize, size: CGSize
) async throws -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    let session = FestivalSession(factory: { client })
    let song = try #require(try await session.catalog().catalog.songs.first {
        $0.songId == LongBandBoardsTransport.songId
    })
    let host = nativeHostedView(
        SongBandLeaderboardScreen(
            session: session, song: song, bandType: "Band_Duets",
            focus: SongBandRowFocus(
                bandId: "fade-band-\(BandRevealID.focusedRank)", bandType: "Band_Duets",
                teamKey: "fade-team-\(BandRevealID.focusedRank)"
            )
        )
        // Fades on (the hosted root turns them off for still captures).
        .environment(\.festivalFadeInEnabled, true)
        .environment(\._accessibilityReduceMotion, reduceMotion)
        .environment(\.dynamicTypeSize, typeSize)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    return (host, nativeHostedWindow(host, size: size))
}

/// Wait until the board has revealed and scrolled to the focused row: the spinner has
/// left the tree and the row sits, settled, inside the host's height.
///
/// - Returns: The focused row's frame.
@MainActor
private func awaitFocusedRow(
    in host: NSView, height: CGFloat, budget: inout NativeHostedPollBudget
) async throws -> CGRect {
    var last: CGRect?
    while true {
        host.layoutSubtreeIfNeeded()
        let spinnerGone = nativeHostedAccessibilityElement(BandRevealID.spinner, in: host) == nil
        let frame = nativeHostedAccessibilityFrame(BandRevealID.focused, in: host)
        if spinnerGone, let frame, frame.minY >= 0, frame.maxY <= height,
           let previous = last, abs(previous.minY - frame.minY) < 0.5 {
            return frame
        }
        last = frame
        try #require(
            !budget.isExhausted,
            "the board revealed and scrolled to the rank-\(BandRevealID.focusedRank) band (spinner gone: \(spinnerGone), frame: \(String(describing: frame)))"
        )
        try await budget.sleep(for: .milliseconds(50))
    }
}

// MARK: - Tests

/// Issue #386 for #327: while the band board loads, VoiceOver finds one spinner element
/// spoken "Loading band scores"; once the reveal has grown the content and scrolled to
/// the focused band, the spinner has left the tree and the band's row is in view as one
/// button labelled "Your band, Rank 20, …" (the highlight's state is spoken, as on the
/// Solo board; leaderboard-row R7), at least 28×28 pt (HIG Accessibility, macOS minimum
/// control size), and the page reads header, rows by rank, then pager. With Reduce
/// Motion the jump is instant and nothing waits on a fade (load-transition R6; HIG
/// Accessibility: "When Reduce Motion is on, reduce automatic and repetitive animation").
@MainActor
@Test(arguments: BandRevealMotion.allCases)
func songBandBoardRevealsTheFocusedBandToAssistiveTechnology(motion: BandRevealMotion) async throws {
    let transport = HeldBandBoardTransport()
    let size = CGSize(width: 402, height: 700)
    let (host, window) = try await hostBandBoard(
        transport, reduceMotion: motion == .reduceMotion, typeSize: .large, size: size
    )
    defer { window.orderOut(nil) }

    // Loading: the spinner is one element with its spoken label, and no row is exposed.
    var budget = NativeHostedPollBudget(.seconds(30))
    var spinner: NSObject?
    while spinner == nil {
        host.layoutSubtreeIfNeeded()
        spinner = nativeHostedAccessibilityElement(BandRevealID.spinner, in: host)
        if spinner != nil { break }
        try #require(!budget.isExhausted, "the spinner is exposed while the board loads")
        try await budget.sleep(for: .milliseconds(20))
    }
    #expect(spinner.flatMap { bandRevealAttribute($0, "accessibilityLabel") as? String } == "Loading band scores")
    #expect(
        !nativeHostedAccessibility(host).identifiers.contains { $0.hasPrefix(BandRevealID.rowPrefix) },
        "no band row is exposed while loading"
    )

    await transport.release()
    let frame = try await awaitFocusedRow(in: host, height: size.height, budget: &budget)

    // The focused band: a button whose label speaks the highlight.
    let row = try #require(nativeHostedAccessibilityElement(BandRevealID.focused, in: host))
    let role = bandRevealAttribute(row, "accessibilityRole") as? String
    #expect(role == NSAccessibility.Role.button.rawValue, "the band's row is a button (\(String(describing: role)))")
    let label = bandRevealAttribute(row, "accessibilityLabel") as? String ?? ""
    #expect(label.hasPrefix("Your band, Rank \(BandRevealID.focusedRank), "), "the highlight is spoken (\(label))")
    #expect(frame.width >= 28 && frame.height >= 28, "the row is at least 28×28 pt (\(frame))")

    // Reading order: the song header, the realized rows by rank, then the pager.
    let ids = nativeHostedAccessibility(host).identifiers
    #expect(!ids.contains(BandRevealID.spinner), "the spinner left the tree")
    let rowIds = ids.filter { BandRevealID.rank($0) != nil }
    let ranks = rowIds.compactMap(BandRevealID.rank)
    #expect(ranks.contains(BandRevealID.focusedRank))
    #expect(ranks == ranks.sorted(), "rows read by rank (\(ranks))")
    let headerIndex = try #require(ids.firstIndex(of: BandRevealID.header), "the song header is exposed (\(ids))")
    let firstRow = try #require(ids.firstIndex { BandRevealID.rank($0) != nil })
    let lastRow = try #require(ids.lastIndex { BandRevealID.rank($0) != nil })
    let pager = try #require(ids.firstIndex { $0.hasPrefix(BandRevealID.pagerPrefix) }, "the pager is exposed (\(ids))")
    #expect(headerIndex < firstRow && lastRow < pager, "header, rows, then pager (\(ids))")

    // Only the focused band speaks the highlight; every other band is a plain button.
    for id in rowIds where id != BandRevealID.focused {
        guard let other = nativeHostedAccessibilityElement(id, in: host) else { continue }
        let otherLabel = bandRevealAttribute(other, "accessibilityLabel") as? String ?? ""
        #expect(otherLabel.hasPrefix("Rank "), "\(id) reads its rank first (\(otherLabel))")
        #expect(bandRevealAttribute(other, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue)
    }
}

/// Issue #386: at an accessibility text size the revealed band's row keeps its label and
/// button role, stays inside the window's width, and grows to fit its larger, stacked
/// score line rather than clipping it (HIG Typography: "Make sure your app's layout
/// adapts to all font sizes"; leaderboard-row R2: rows may grow at accessibility sizes).
@MainActor
@Test func songBandBoardFocusedRowGrowsAtAccessibilityTextSizes() async throws {
    let size = CGSize(width: 402, height: 900)
    var frames: [DynamicTypeSize: CGRect] = [:]
    var labels: [DynamicTypeSize: String] = [:]
    for typeSize in [DynamicTypeSize.large, .accessibility5] {
        let transport = HeldBandBoardTransport()
        let (host, window) = try await hostBandBoard(transport, reduceMotion: true, typeSize: typeSize, size: size)
        defer { window.orderOut(nil) }
        await transport.release()
        var budget = NativeHostedPollBudget(.seconds(30))
        frames[typeSize] = try await awaitFocusedRow(in: host, height: size.height, budget: &budget)
        let row = try #require(nativeHostedAccessibilityElement(BandRevealID.focused, in: host))
        labels[typeSize] = bandRevealAttribute(row, "accessibilityLabel") as? String
        #expect(bandRevealAttribute(row, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue)
    }
    let standard = try #require(frames[.large])
    let large = try #require(frames[.accessibility5])
    #expect(labels[.large] == labels[.accessibility5], "the spoken label does not depend on text size")
    #expect(large.minX >= 0 && large.maxX <= size.width, "the row stays inside the window (\(large))")
    #expect(large.height > standard.height * 1.35, "the row grows at AX5 (\(standard.height) → \(large.height))")
}
#endif
