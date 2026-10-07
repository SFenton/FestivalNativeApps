#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// Issue #323: a selected-row reveal that lands while a page's first-load fade is still
// running must not show the rows it reaches already opaque. These journeys open each
// board for a row past the first screen (index ≥ 8, the case whose reveal started just
// as the old settle timer stopped fading rows), sample the row by its accessibility
// frame and capture it as soon as it is on screen.
//
// Captures do show in-flight SwiftUI animations, but the rushed fade (400 ms) mostly
// overlaps the scroll (350 ms), so a loaded host could miss it. Each journey therefore
// stretches the item fades' curve (`festivalFadeInItemCurve`) to a slow linear one; the
// page scope's timing, the reveal's wait, the scroll and the reload gate's block fade
// keep their real values.

// MARK: - Fixture transport

/// Keyless fixture transport for a 60-account Lead Full Rankings board (25 a page) with
/// the selected player at rank 45, on page 2, plus their single-account spotlight read.
/// Rejects the privileged key, selected-profile headers, writes and any other route.
private actor LongRankingsTransport: HTTPTransport {
    private let generation = 31
    static let selectedAccount = "fixture-reveal-player"
    static let selectedRank = 45
    static let total = 60

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
        guard request.value(forHTTPHeaderField: "X-FST-Publication-Id") == String(generation) else {
            throw FestivalAPIError.invalidPublication
        }
        let pinned = ["X-FST-Publication-Id": String(generation)]
        let parts = url.pathComponents
        guard parts.count >= 4, parts[1] == "api", parts[2] == "rankings", parts[3] != "bands" else {
            throw FestivalAPIError.httpStatus(404)
        }
        let instrument = parts[3]
        if parts.count == 5 {
            guard parts[4] == Self.selectedAccount else { throw FestivalAPIError.httpStatus(404) }
            var body = Self.entry(rank: Self.selectedRank)
            body["instrument"] = instrument
            body["totalRankedAccounts"] = Self.total
            return HTTPResult(status: 200, data: try JSONSerialization.data(withJSONObject: body), headers: pinned)
        }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        let page = Int(query["page"] ?? "1") ?? 1
        let pageSize = Int(query["pageSize"] ?? "25") ?? 25
        let first = (page - 1) * pageSize + 1
        let entries = (first..<min(first + pageSize, Self.total + 1)).map(Self.entry(rank:))
        return HTTPResult(status: 200, data: try JSONSerialization.data(withJSONObject: [
            "instrument": instrument, "rankBy": query["rankBy"] ?? "totalscore", "page": page,
            "pageSize": pageSize, "totalAccounts": Self.total, "entries": entries,
        ] as [String: Any]), headers: pinned)
    }

    /// One account row: the selected player at their rank, a fixture account elsewhere.
    private static func entry(rank: Int) -> [String: Any] {
        let selected = rank == selectedRank
        return [
            "accountId": selected ? selectedAccount : "fixture-ranked-\(rank)",
            "displayName": selected ? "Reveal Player" : "Ranked \(rank)",
            "songsPlayed": 40, "totalChartedSongs": 50, "coverage": 0.8,
            "rawSkillRating": 0.02, "adjustedSkillRating": 0.02, "adjustedSkillRank": rank,
            "weightedRating": 0.03, "weightedRank": rank, "fcRate": 0.5, "fcRateRank": rank,
            "totalScore": 90_000_000 - rank * 1000, "totalScoreRank": rank,
            "maxScorePercent": 0.97, "maxScorePercentRank": rank, "avgAccuracy": 0.98,
            "fullComboCount": 20, "avgStars": 4.8, "bestRank": 1, "avgRank": 2.5,
        ]
    }
}

// MARK: - Journey

/// The motion setting a journey renders with.
enum RevealMotion: String, CaseIterable, CustomTestStringConvertible {
    case standard, reduceMotion

    var testDescription: String { rawValue }
}

/// The three boards with a selected-row reveal.
enum RevealBoard: String, CaseIterable, CustomTestStringConvertible {
    case solo, songBand, fullRankings

    var testDescription: String { rawValue }

    /// The selected row's accessibility identifier: the 20th row of its page.
    var rowId: String {
        switch self {
        case .solo: "fst.song-leaderboard.row.fixture-spotlight-player"
        case .songBand: "fst.song-band-leaderboard.row.fade-band-20:20"
        case .fullRankings: "fst.rankings.row.\(LongRankingsTransport.selectedAccount)"
        }
    }

    /// Mean channel value above which a sample is row text (each board's settled row
    /// text measures well above it, its card well below).
    var threshold: Int {
        switch self {
        case .solo: 80
        case .songBand, .fullRankings: 110
        }
    }

    /// The board, opened for its selected row (Full Rankings opens on page 1; its
    /// footer jump opens the selected player's page).
    @MainActor
    func screen() async throws -> AnyView {
        switch self {
        case .solo:
            let session = try await spotlightSelectedSession()
            let song = try spotlightFixtureSong()
            let payload = try spotlightFixtureLeaderboard(spotlightRank: 20)
            return AnyView(NavigationStack {
                SoloLeaderboardScreen(
                    song: song, instrument: .lead, session: session, initialPage: 1,
                    path: .constant([]), focusSelected: true, initialState: .loaded(payload)
                )
            })
        case .songBand:
            let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongBandBoardsTransport())
            let session = FestivalSession(factory: { client })
            let song = try #require(try await session.catalog().catalog.songs.first {
                $0.songId == LongBandBoardsTransport.songId
            })
            return AnyView(SongBandLeaderboardScreen(
                session: session, song: song, bandType: "Band_Duets",
                focus: SongBandRowFocus(bandId: "fade-band-20", bandType: "Band_Duets", teamKey: "fade-team-20")
            ))
        case .fullRankings:
            let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongRankingsTransport())
            let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
            {"accountId":"\(LongRankingsTransport.selectedAccount)","displayName":"Reveal Player"}
            """.utf8))
            let session = FestivalSession(
                factory: { client }, debugSelectedPlayer: try SelectedPlayerIdentity(searchResult: result)
            )
            return AnyView(FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore"))
        }
    }
}

/// A capture of the selected row while it sat wholly in the clear part of the page.
struct RevealSample {
    /// The row's frame, in host points.
    let frame: CGRect
    /// Bright (text) samples inside it.
    let bright: Int
}

/// The test-only slow item fade (see the file comment).
private let slowedItemFade = Animation.linear(duration: 3)

/// Watch `row` until it rests in the clear band, recording the first capture with the row
/// wholly inside the band and the settled one: at least `rest` later, once two captures
/// in a row (150 ms apart) agree on its frame and text.
///
/// - Parameters:
///   - host: The board's host, in its window.
///   - size: The host's size.
///   - row: The row's accessibility identifier.
///   - band: The clear vertical band (below the bar, above the pinned chrome's fade).
///   - threshold: Bright-sample threshold for row text.
///   - rest: Least time from the first in-band capture to the settled one.
///   - timeout: Upper bound for the row to arrive and settle (scaled in a VM).
/// - Returns: The first in-band and the settled captures.
@MainActor
private func watchReveal<Content: View>(
    _ host: NSHostingView<Content>, size: CGSize, row: String, band: ClosedRange<CGFloat>,
    threshold: Int, rest: Duration, timeout: Duration = .seconds(60)
) async throws -> (first: RevealSample, settled: RevealSample) {
    let clock = ContinuousClock()
    let deadline = clock.now + nativeHostedReadinessBudget(timeout)
    var first: (sample: RevealSample, at: ContinuousClock.Instant)?
    var previous: RevealSample?
    while clock.now < deadline {
        host.layoutSubtreeIfNeeded()
        if let frame = nativeHostedAccessibilityFrame(row, in: host),
           frame.minY >= band.lowerBound, frame.maxY <= band.upperBound {
            let image = try nativeHostedImage(host)
            let sample = RevealSample(
                frame: frame,
                bright: nativeHostedBrightSamples(in: frame, of: image, hostSize: size, threshold: threshold)
            )
            guard let first else {
                first = (sample, clock.now)
                continue
            }
            if clock.now - first.at >= rest {
                if let previous, previous.bright == sample.bright,
                   abs(previous.frame.minY - sample.frame.minY) < 0.5 {
                    return (first.sample, sample)
                }
                previous = sample
                try await Task.sleep(for: .milliseconds(150))
                continue
            }
        } else {
            previous = nil
        }
        try await Task.sleep(for: .milliseconds(first == nil ? 20 : 100))
    }
    Issue.record("\(row) never rested in the clear band \(band)")
    throw CancellationError()
}

/// Issue #323: each board opened for a row past its first screen (the solo board from
/// Song Detail's score, the band board from a band preview, Full Rankings from its
/// pinned footer's jump to the player's page while that page is still fading in) waits
/// for the row's entrance and then scrolls it to the centre. The row the scroll reaches
/// fades in with the rush rather than arriving already opaque. With Reduce Motion the
/// row appears without a fade and the scroll is instant (load-transition R6).
@MainActor
@Test(.serialized, arguments: RevealBoard.allCases, RevealMotion.allCases)
func selectedRowRevealFadesTheRowItReaches(board: RevealBoard, motion: RevealMotion) async throws {
    let size = CGSize(width: 402, height: 700)
    let reduceMotion = motion == .reduceMotion
    let host = nativeHostedView(
        try await board.screen()
            // Fades on (the hosted root turns them off for still captures).
            .environment(\.festivalFadeInEnabled, true)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .environment(\.festivalFadeInItemCurve, slowedItemFade)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }

    if board == .fullRankings {
        // Jump from the pinned footer as soon as it offers it, while page 1 still fades.
        let clock = ContinuousClock()
        let deadline = clock.now + nativeHostedReadinessBudget(.seconds(30))
        var jump: NSObject?
        while jump == nil, clock.now < deadline {
            host.layoutSubtreeIfNeeded()
            jump = nativeHostedAccessibilityElement("fst.full-rankings.spotlight-jump", in: host)
            if jump == nil { try await Task.sleep(for: .milliseconds(30)) }
        }
        let press: AnyObject = try #require(jump, "the footer offers a jump to the player's page")
        #expect(press.accessibilityPerformPress?() == true)
    }

    // Below the bar and above the pinned footer/pager and their 36 pt fade.
    let band: ClosedRange<CGFloat> = 90...(size.height - 230)
    let (first, settled) = try await watchReveal(
        host, size: size, row: board.rowId, band: band, threshold: board.threshold,
        rest: reduceMotion ? .seconds(1) : .seconds(3.5)
    )
    _ = try nativeHostedPNG(
        try nativeHostedImage(host), filename: "reveal-\(board.rawValue)-\(motion.rawValue).png",
        environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    #expect(settled.bright > 100, "the settled row's text is drawn (\(settled.bright))")
    if reduceMotion {
        #expect(
            Double(first.bright) >= Double(settled.bright) * 0.9,
            "with Reduce Motion the row arrives fully drawn (\(first.bright) of \(settled.bright))"
        )
        #expect(abs(first.frame.minY - settled.frame.minY) < 2, "with Reduce Motion the scroll is instant")
    } else {
        #expect(
            Double(first.bright) < Double(settled.bright) * 0.5,
            "the row the scroll reaches is still fading in (\(first.bright) of \(settled.bright))"
        )
    }
}

// MARK: - List rows

/// A linear test curve that records each frame SwiftUI asks it for, so a test can tell an
/// animated commit from a plain one without catching a frame mid-fade (the `apple-ci` VM
/// runs the hosted bundle on one main actor and can stall captures for seconds).
struct RecordingFadeCurve: CustomAnimation {
    /// Identifies this curve's frames in ``RecordingFadeCurve/frames``.
    let key: String
    /// The fade's length, in seconds.
    let duration: TimeInterval

    nonisolated(unsafe) private static var log: [String: [TimeInterval]] = [:]
    private static let lock = NSLock()

    /// The elapsed times SwiftUI animated `key` at, in order.
    static func frames(_ key: String) -> [TimeInterval] {
        lock.withLock { log[key] ?? [] }
    }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        Self.lock.withLock { Self.log[key, default: []].append(time) }
        guard time < duration else { return nil }
        return value.scaled(by: time / duration)
    }
}

/// Six rows of a `List` with the canonical scoped stagger, each fading on its own
/// ``RecordingFadeCurve``.
private struct StaggeredListProbe: View {
    /// Prefix of each row's curve key (`<probe>.<index>`).
    let probe: String
    /// Each row's fade length, in seconds.
    let duration: TimeInterval

    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { index in
                Text("Row \(index)")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("fst.test.staggered-row.\(index)")
                    .festivalFadeIn(staggerIndex: index)
                    .environment(\.festivalFadeInItemCurve, Animation(
                        RecordingFadeCurve(key: "\(probe).\(index)", duration: duration)
                    ))
                    .listRowBackground(Color.black)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .festivalScrollFadeInScope(nil, resetKey: 1)
        .environment(\.festivalFadeInEnabled, true)
    }
}

/// A `List` row whose staggered fade waited on its page scope fades in rather than
/// popping in: a plain state write in the same update as the animated reveal made the
/// row commit without animation (macOS, found under #323). Each row's curve records the
/// frames SwiftUI animates it with, so the check does not depend on a capture landing
/// mid-fade; captures of the first row still prove it ends fully drawn and, when two land
/// close together, that it did not jump from hidden to drawn.
@MainActor
@Test func staggeredListRowsFadeInRatherThanPop() async throws {
    let size = CGSize(width: 400, height: 500)
    let probe = "staggered-list-\(UUID().uuidString)"
    let fade: TimeInterval = 2
    let host = nativeHostedView(
        StaggeredListProbe(probe: probe, duration: fade).preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let clock = ContinuousClock()
    let deadline = clock.now + nativeHostedReadinessBudget(.seconds(60))
    var samples: [(dim: Int, bright: Int, at: ContinuousClock.Instant)] = []
    var drawnAt: ContinuousClock.Instant?
    let rows = 0..<6
    func frames() -> [[TimeInterval]] { rows.map { RecordingFadeCurve.frames("\(probe).\($0)") } }
    while clock.now < deadline {
        host.layoutSubtreeIfNeeded()
        if let frame = nativeHostedAccessibilityFrame("fst.test.staggered-row.0", in: host) {
            let image = try nativeHostedImage(host)
            samples.append((
                nativeHostedBrightSamples(in: frame, of: image, hostSize: size, threshold: 60),
                nativeHostedBrightSamples(in: frame, of: image, hostSize: size, threshold: 200),
                clock.now
            ))
        }
        if let last = samples.last, last.bright > 100 {
            drawnAt = drawnAt ?? clock.now
            // Every row's fade has ended, or the first row has stayed drawn for a whole
            // fade (a popped row never records a frame).
            let finished = frames().allSatisfy { $0.contains { $0 >= fade } }
            if finished || clock.now - (drawnAt ?? clock.now) > .seconds(fade + 1) { break }
        } else {
            drawnAt = nil
        }
        try await Task.sleep(for: .milliseconds(30))
    }
    let final = try #require(samples.last, "the first row is revealed")
    #expect(final.bright > 100, "the first row ends fully drawn (\(final.bright))")
    // The pop committed every row that waited on the scope unanimated. Under a saturated
    // main actor a `List` can rebuild a row after the page window closed, and that row
    // rightly shows without a fade (load-transition R5), so not every row must animate.
    let recorded = frames()
    #expect(
        recorded.contains { !$0.isEmpty },
        "the staggered rows commit with their fade rather than popping in (frames per row: \(recorded.map(\.count)))"
    )
    // Two captures 400 ms apart cannot span a 2 s fade from hidden to fully drawn.
    let popped = zip(samples, samples.dropFirst()).contains { before, after in
        after.at - before.at < .milliseconds(400) && before.dim < final.dim / 10 && after.bright >= final.bright * 9 / 10
    }
    #expect(!popped, "the first row jumps from hidden to drawn (\(samples.map { "\($0.dim)/\($0.bright)" }))")
}
#endif
