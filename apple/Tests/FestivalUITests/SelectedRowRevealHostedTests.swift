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
// The fade is sampled by explicit progress, not by when a capture lands (issue #327):
// each journey replaces the item fades' curve (`festivalFadeInItemCurve`) with a
// ``HeldFadeCurve`` that holds every item fade at its start until the test releases it.
// A row that commits with its fade is therefore still undrawn whenever it is first
// captured, however long the `apple-ci` VM stalls; a row that arrives opaque is drawn.
// The page scope runs on a frozen clock (`festivalFadeInFrozenTime`), so a stall cannot close
// its rush window before the scroll reaches the row; the reveal's wait, the scroll and
// the reload gate's block fade keep their real timing. `FadeInOnLoadTests` checks the
// scope's ordering (rows past the first screen held for the scroll, rushed with it)
// through the model. Every phase of a journey shares one short wall-clock deadline
// (`NativeHostedEvidenceDeadline`, 10 s; alone a journey takes about 4 s): it starts once
// the shared main actor responds, waiting 5 s of it at most, and captures only the row's
// rect. At the parallel bundle's peak SwiftUI evaluates almost no animation frames and can
// render an animated commit at its end, so a starved journey's fade evidence is a known
// issue rather than a verdict (and never a hang); a responsive one is judged strictly.

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

/// What ``watchReveal(_:row:band:threshold:drawn:fade:deadline:)`` saw.
struct RevealWatch {
    /// The first capture with the row wholly in the clear band, taken while every item
    /// fade was still held at its start.
    let first: RevealSample
    /// The settled capture, after the held fades were released and had ended.
    let settled: RevealSample
    /// Opacity frames SwiftUI animated the page's item fades with, held or released, by the
    /// settled capture (0 when no item fade ran, as under Reduce Motion). A loaded host
    /// may tick none while the fades are held, but a fade on the curve ends only on a
    /// released frame.
    let frames: Int
    /// Why the host was too starved for its rendered frames to show a fade, or nil when
    /// it stayed responsive (see `nativeHostedStarvedLag`).
    var starved: String?
}

// MARK: - Held fade curve

/// An item-fade curve whose progress the test sets explicitly (issue #327): every fade's
/// opacity on it stays at its start (hidden; see ``heldProgress``) until
/// ``HeldFadeCurve/release(_:)``, then ends on the next frame; everything else the same
/// transaction animates (the rise, layout) ends at once. A capture therefore tells a row
/// that committed with its fade (undrawn, whenever the capture lands) from one that
/// arrived opaque (drawn), with no wall-clock sampling: the `apple-ci` VM stalls the
/// shared main actor for seconds, long enough for a timed fade to finish between two
/// captures.
struct HeldFadeCurve: CustomAnimation {
    /// Identifies this curve's state (one key per journey).
    let key: String

    private struct State {
        var released = false
        /// Opacity frames requested, held or released.
        var frames = 0
    }

    /// The most progress a held fade makes (0.01%: invisible). It creeps toward it rather
    /// than staying exactly at the start: a curve that keeps returning its start value
    /// makes SwiftUI re-evaluate it about 20 times as often as a running fade, which
    /// starved every hosted test running alongside.
    static let heldProgress = 1e-4

    nonisolated(unsafe) private static var states: [String: State] = [:]
    private static let lock = NSLock()

    /// Let every fade on `key` end at its next frame.
    static func release(_ key: String) {
        lock.withLock { states[key, default: State()].released = true }
    }

    /// Opacity frames SwiftUI has animated `key` with.
    static func frames(_ key: String) -> Int {
        lock.withLock { states[key]?.frames ?? 0 }
    }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        // Only opacity is held: it is the evidence. The same transaction also animates the
        // rise and any layout the reveal causes; those end at once, so the row's frame is
        // final when the test checks that it lies in the band.
        guard V.self == Double.self else { return nil }
        let released = Self.lock.withLock {
            Self.states[key, default: State()].frames += 1
            return Self.states[key, default: State()].released
        }
        // Held: within `heldProgress` of the start. Released: done, at the final value.
        return released ? nil : value.scaled(by: Self.heldProgress * (1 - exp(-time)))
    }
}

/// Watch `row` until it lies wholly in the clear band and capture it while the item fades
/// are held (`first`), then release them and capture it again once it has settled: its
/// text is drawn (over `drawn` samples) and two captures in a row (150 ms apart) agree on
/// its frame and, within 2%, its text. The released fade ends on the row's next animation
/// frame, which a loaded host may tick only after other rows' frames, so the wait is for
/// the drawn row rather than for any fade on the curve to end. Each capture renders only
/// the row's rect (`nativeHostedImage(_:in:)`). Every wait is a condition bounded by the
/// journey's shared wall-clock `deadline`, which throws ``NativeHostedEvidenceExpired``
/// when it passes. Nothing depends on when a capture lands.
///
/// - Parameters:
///   - host: The board's host, in its window.
///   - row: The row's accessibility identifier.
///   - band: The clear vertical band (below the bar, above the pinned chrome's fade).
///   - threshold: Bright-sample threshold for row text.
///   - drawn: Bright samples the settled row's text exceeds.
///   - fade: The page's ``HeldFadeCurve`` key.
///   - deadline: The journey's shared deadline; its polls record their lag on it.
/// - Returns: The held and settled captures and the frames animated on the curve.
/// - Throws: ``NativeHostedEvidenceExpired`` when the deadline passes first.
@MainActor
private func watchReveal<Content: View>(
    _ host: NSHostingView<Content>, row: String, band: ClosedRange<CGFloat>,
    threshold: Int, drawn: Int = 100, fade: String, deadline: inout NativeHostedEvidenceDeadline
) async throws -> RevealWatch {
    /// The row's capture when it lies wholly in the band, else nil.
    func capture() throws -> RevealSample? {
        host.layoutSubtreeIfNeeded()
        guard let frame = nativeHostedAccessibilityFrame(row, in: host),
              frame.minY >= band.lowerBound, frame.maxY <= band.upperBound else { return nil }
        return RevealSample(
            frame: frame,
            bright: nativeHostedBrightSamples(
                in: CGRect(origin: .zero, size: frame.size), of: try nativeHostedImage(host, in: frame),
                hostSize: frame.size, threshold: threshold
            )
        )
    }

    // Each loop looks once more before it gives up: a starved poll can resume past the
    // deadline with the row already in place.
    var first = try capture()
    while first == nil {
        try deadline.check(
            "\(row) had not lain wholly in the clear band \(band) (frame \(String(describing: nativeHostedAccessibilityFrame(row, in: host))))"
        )
        try await deadline.sleep(for: .milliseconds(20))
        first = try capture()
    }
    guard let first else { throw CancellationError() }

    HeldFadeCurve.release(fade)
    var previous: RevealSample?
    while true {
        let sample = try capture().flatMap { $0.bright > drawn ? $0 : nil }
        if let sample, let previous, abs(previous.bright - sample.bright) <= max(2, sample.bright / 50),
           abs(previous.frame.minY - sample.frame.minY) < 0.5 {
            return RevealWatch(first: first, settled: sample, frames: HeldFadeCurve.frames(fade))
        }
        previous = sample
        try deadline.check(
            "\(row) had not settled drawn in the clear band \(band) after its fade (last \(String(describing: previous)))"
        )
        try await deadline.sleep(for: .milliseconds(150))
    }
}

/// Open `board` for its selected row (Full Rankings: jump from its pinned footer while
/// page 1 still fades) and watch the row arrive, within one shared deadline.
///
/// - Parameters:
///   - board: The board to open.
///   - motion: The motion setting to render with.
///   - size: The host's size.
/// - Returns: What the watch saw, with the deadline's starvation verdict.
/// - Throws: ``NativeHostedEvidenceExpired`` when the deadline passes first.
@MainActor
private func runRevealJourney(board: RevealBoard, motion: RevealMotion, size: CGSize) async throws -> RevealWatch {
    let reduceMotion = motion == .reduceMotion
    let fade = "reveal-\(board.rawValue)-\(motion.rawValue)-\(UUID().uuidString)"
    // Released on every exit, an expired deadline or a thrown capture included: a held
    // curve keeps SwiftUI requesting frames for every row on it.
    defer { HeldFadeCurve.release(fade) }
    var deadline = NativeHostedEvidenceDeadline()
    // Rendered fade frames are the evidence: start once the shared main actor responds.
    try await deadline.awaitResponsiveMainActor()
    let frozen = ProcessInfo.processInfo.systemUptime
    let host = nativeHostedView(
        try await board.screen()
            // Fades on (the hosted root turns them off for still captures).
            .environment(\.festivalFadeInEnabled, true)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .environment(\.festivalFadeInItemCurve, Animation(HeldFadeCurve(key: fade)))
            // Frozen scope clock: a stall between the scroll's start and its first
            // movement can't close the rush window the reached rows fade in with.
            .environment(\.festivalFadeInFrozenTime, frozen)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }

    if board == .fullRankings {
        // Jump from the pinned footer as soon as it offers it, while page 1 still fades.
        func findJump() -> NSObject? {
            host.layoutSubtreeIfNeeded()
            return nativeHostedAccessibilityElement("fst.full-rankings.spotlight-jump", in: host)
        }
        var jump = findJump()
        while jump == nil {
            try deadline.check("the footer had not offered its jump to the player's page")
            try await deadline.sleep(for: .milliseconds(30))
            jump = findJump()
        }
        let press: AnyObject = try #require(jump, "the footer offers a jump to the player's page")
        #expect(press.accessibilityPerformPress?() == true)
    }

    // Below the bar and above the pinned footer/pager and their 40 pt fade.
    let band: ClosedRange<CGFloat> = 90...(size.height - 230)
    var watch = try await watchReveal(
        host, row: board.rowId, band: band, threshold: board.threshold, fade: fade, deadline: &deadline
    )
    watch.starved = deadline.starved
    if ProcessInfo.processInfo.environment["FST_LEADERBOARDS_RENDER_OUT"] != nil {
        _ = try nativeHostedPNG(
            try nativeHostedImage(host), filename: "reveal-\(board.rawValue)-\(motion.rawValue).png",
            environment: "FST_LEADERBOARDS_RENDER_OUT"
        )
    }
    return watch
}

/// Issue #323: each board opened for a row past its first screen (the solo board from
/// Song Detail's score, the band board from a band preview, Full Rankings from its
/// pinned footer's jump to the player's page while that page is still fading in) waits
/// for the row's entrance and then scrolls it to the centre. The row the scroll reaches
/// fades in with the rush rather than arriving already opaque. With Reduce Motion the
/// row appears without a fade and the scroll is instant (load-transition R6).
///
/// Every item fade is held at its start until the row has arrived (``HeldFadeCurve``), so
/// the first capture shows whether the row committed with its fade (undrawn) or opaque
/// (drawn) however late it lands (issue #327). The whole journey shares one 10 s
/// wall-clock deadline (``NativeHostedEvidenceDeadline``). When the shared main actor was
/// starved, SwiftUI may have committed even a faded row at its end without calling the
/// curve, so the fade evidence (or an expired deadline) is recorded as an intermittent
/// known issue rather than judged; on a responsive host both are judged strictly. Reduce
/// Motion's evidence (no fade, drawn, instant) holds either way once the row arrives.
@MainActor
@Test(.serialized, arguments: RevealBoard.allCases, RevealMotion.allCases)
func selectedRowRevealFadesTheRowItReaches(board: RevealBoard, motion: RevealMotion) async throws {
    let size = CGSize(width: 402, height: 700)
    let watch: RevealWatch
    do {
        watch = try await runRevealJourney(board: board, motion: motion, size: size)
    } catch let expired as NativeHostedEvidenceExpired {
        nativeHostedRecordExpired(expired)
        return
    }
    let (first, settled) = (watch.first, watch.settled)
    #expect(settled.bright > 100, "the settled row's text is drawn (\(settled.bright))")
    if motion == .reduceMotion {
        #expect(watch.frames == 0, "with Reduce Motion no item fades (\(watch.frames) frames)")
        #expect(
            Double(first.bright) >= Double(settled.bright) * 0.9,
            "with Reduce Motion the row arrives fully drawn (\(first.bright) of \(settled.bright))"
        )
        #expect(abs(first.frame.minY - settled.frame.minY) < 2, "with Reduce Motion the scroll is instant")
    } else {
        func expectFade() {
            #expect(watch.frames > 0, "the page's item fades run on the held curve")
            #expect(
                Double(first.bright) < Double(settled.bright) * 0.5,
                "the row the scroll reaches is still fading in (\(first.bright) of \(settled.bright))"
            )
        }
        if let starved = watch.starved {
            withKnownIssue("Starved host (\(starved)): its rendered frames can't show a fade", isIntermittent: true) {
                expectFade()
            }
        } else {
            expectFade()
        }
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
/// close together, that it did not jump from hidden to drawn. The journey shares one
/// wall-clock deadline (``NativeHostedEvidenceDeadline``, issue #327).
@MainActor
@Test func staggeredListRowsFadeInRatherThanPop() async throws {
    var deadline = NativeHostedEvidenceDeadline()
    try await deadline.awaitResponsiveMainActor()
    let size = CGSize(width: 400, height: 500)
    let probe = "staggered-list-\(UUID().uuidString)"
    let fade: TimeInterval = 2
    let suite = "fst.tests.staggered-list.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        StaggeredListProbe(probe: probe, duration: fade)
            // Motion on: GitHub's macOS runner image turns the system Reduce Motion on
            // (actions/runner-images `configure-system.sh`), which shows the rows at once.
            .environment(\._accessibilityReduceMotion, false)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let clock = ContinuousClock()
    // Each capture's poll interval (`from` before layout, `to` after sampling): the
    // capture happened somewhere inside it, however long the main actor stalled there.
    var samples: [(dim: Int, bright: Int, from: ContinuousClock.Instant, to: ContinuousClock.Instant)] = []
    var drawnAt: ContinuousClock.Instant?
    let rows = 0..<6
    func frames() -> [[TimeInterval]] { rows.map { RecordingFadeCurve.frames("\(probe).\($0)") } }
    do {
        while true {
            let from = clock.now
            host.layoutSubtreeIfNeeded()
            if let frame = nativeHostedAccessibilityFrame("fst.test.staggered-row.0", in: host) {
                // Only the row's rect: cheap, so two captures land close together.
                let image = try nativeHostedImage(host, in: frame)
                let rect = CGRect(origin: .zero, size: frame.size)
                samples.append((
                    nativeHostedBrightSamples(in: rect, of: image, hostSize: frame.size, threshold: 60),
                    nativeHostedBrightSamples(in: rect, of: image, hostSize: frame.size, threshold: 200),
                    from, clock.now
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
            try deadline.check(
                "the first row had not stayed drawn for a whole fade (samples \(samples.map { "\($0.dim)/\($0.bright)" }))"
            )
            try await deadline.sleep(for: .milliseconds(30))
        }
    } catch let expired as NativeHostedEvidenceExpired {
        nativeHostedRecordExpired(expired)
        return
    }
    let starved = deadline.starved
    func expectFade() throws {
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
        // Two captures at most 400 ms apart cannot span a 2 s fade from hidden to fully drawn.
        // Bounded by the earlier poll's start and the later one's end, so a stall inside a
        // poll widens the bound rather than hiding a fade's progress (issue #327).
        let popped = zip(samples, samples.dropFirst()).contains { before, after in
            after.to - before.from < .milliseconds(400) && before.dim < final.dim / 10 && after.bright >= final.bright * 9 / 10
        }
        #expect(!popped, "the first row jumps from hidden to drawn (\(samples.map { "\($0.dim)/\($0.bright)" }))")
    }
    // A starved host can commit an animated row at its end without calling its curve, so
    // its frames prove nothing either way.
    if let starved {
        try withKnownIssue("Starved host (\(starved)): its rendered frames can't show a fade", isIntermittent: true) {
            try expectFade()
        }
    } else {
        try expectFade()
    }
}
#endif
