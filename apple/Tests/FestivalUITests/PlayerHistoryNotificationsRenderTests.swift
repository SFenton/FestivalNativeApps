#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Minimal keyless fixture transport for `PlayerHistoryScreen`/`NotificationsSheet`
/// hosted renders: publication, songs (for title/art resolution) and the two new
/// personal-data endpoints. Rejects the privileged key and selected-profile headers
/// like the service safety rules require of every fixture, matching the pattern in
/// `ShopScreenRenderTests.swift`.
actor HostedHistoryTransport: HTTPTransport {
    private let generation = 7
    var historyStatus = 200
    /// Extra Lead scores after the three fixture rows (six or more shows View All Scores).
    var extraLeadScores: [Int] = []
    var notificationsBody = Data("""
    {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":1,
     "sourceCompletedAt":"2024-01-05T00:00:00Z","notificationsGenerated":true,"items":[
       {"eventId":1,"notificationGuid":"guid-1","accountId":"fixture-1",
        "eventKind":"player_song_rank_improved","songId":"fixture-song",
        "instrument":"Solo_Guitar","oldRank":42,"newRank":10,
        "detectedAt":"2024-01-05T00:00:00Z","expiresAt":"2024-02-05T00:00:00Z"},
       {"eventId":2,"notificationGuid":"guid-2","accountId":"fixture-1",
        "eventKind":"player_fc_achieved","songId":"fixture-song",
        "instrument":"Solo_Bass",
        "detectedAt":"2024-01-04T00:00:00Z","expiresAt":"2024-02-04T00:00:00Z"},
       {"eventId":3,"notificationGuid":"guid-3","accountId":"fixture-1",
        "eventKind":"player_first_score","songId":"fixture-song","instrument":"Solo_Drums",
        "detectedAt":"2024-01-03T00:00:00Z","expiresAt":"2024-02-03T00:00:00Z",
        "payload":{"coalescedInstruments":["Solo_Drums","Solo_Vocals"],"coalescedEvents":[
          {"eventKind":"player_first_score","instrument":"Solo_Drums","newNumeric":250000},
          {"eventKind":"player_stars_improved","instrument":"Solo_Vocals","oldNumeric":4,"newNumeric":5}]}}
    ]}
    """.utf8)

    /// Replace the fixture `/api/player/{id}/notifications` response body.
    ///
    /// - Parameter body: Raw JSON envelope bytes to serve for subsequent requests.
    func setNotificationsBody(_ body: Data) {
        notificationsBody = body
    }

    /// Serve `/api/player/fixture-1/history` with this status (200 or 202).
    ///
    /// - Parameter status: HTTP status for subsequent history reads.
    func setHistoryStatus(_ status: Int) {
        historyStatus = status
    }

    /// Add Lead scores (dated before the fixture rows) to the history response.
    ///
    /// - Parameter scores: Extra `newScore` values.
    func setExtraLeadScores(_ scores: [Int]) {
        extraLeadScores = scores
    }

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
        if url.path == "/api/songs" {
            return HTTPResult(
                status: 200,
                data: Data("""
                {"count":1,"currentSeason":40,"songs":[
                  {"songId":"fixture-song","title":"Fixture Anthem","artist":"The Fixtures",
                   "album":null,"year":2024,"durationSeconds":180,"albumArt":null,
                   "difficulty":null,"pathArtifactGenerationId":null}
                ]}
                """.utf8),
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        if url.path == "/api/player/fixture-1/history" {
            if historyStatus == 202 {
                return HTTPResult(status: 202, data: Data("""
                {"accountId":"fixture-1","status":"syncing","notYetPublished":true,
                 "count":0,"history":[]}
                """.utf8))
            }
            let extra = extraLeadScores.enumerated().map { index, score in
                """
                ,{"songId":"fixture-song","instrument":"Solo_Guitar","newScore":\(score),
                  "newRank":20,"accuracy":880000,"isFullCombo":false,"season":38,
                  "scoreAchievedAt":"2023-11-\(String(format: "%02d", index + 1))T00:00:00Z",
                  "changedAt":"2023-11-\(String(format: "%02d", index + 1))T00:00:00Z"}
                """
            }.joined()
            return HTTPResult(
                status: 200,
                data: Data("""
                {"accountId":"fixture-1","count":\(3 + extraLeadScores.count),"history":[
                  {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":850000,
                   "newRank":4,"accuracy":991200,"isFullCombo":true,"season":40,
                   "scoreAchievedAt":"2024-01-05T00:00:00Z","changedAt":"2024-01-05T00:00:00Z"},
                  {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":700000,
                   "newRank":9,"accuracy":954500,"isFullCombo":false,"season":39,
                   "scoreAchievedAt":"2024-01-01T00:00:00Z","changedAt":"2024-01-01T00:00:00Z"},
                  {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":600000,
                   "newRank":15,"accuracy":901000,"isFullCombo":false,"season":39,
                   "scoreAchievedAt":"2023-12-20T00:00:00Z","changedAt":"2023-12-20T00:00:00Z"}
                  \(extra)
                ]}
                """.utf8),
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        if url.path == "/api/player/fixture-1/notifications" {
            return HTTPResult(
                status: 200, data: notificationsBody,
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        throw FestivalAPIError.httpStatus(404)
    }
}

/// Build a session with a stored selected profile against the fixture transport.
///
/// - Parameters:
///   - transport: Fixture transport.
///   - accountId: Selected player; nil selects nobody. Accounts other than
///     `fixture-1` get the service's 404 (unregistered).
/// - Returns: The session.
@MainActor
private func hostedHistorySession(
    transport: HostedHistoryTransport, accountId: String? = "fixture-1"
) -> FestivalSession {
    let client = try! FestivalAPI(
        baseURL: URL(string: "http://localhost")!, transport: transport
    )
    let suite = "fst.tests.history.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    if let accountId {
        defaults.set(
            Data("""
            {"accountId":"\(accountId)","displayName":"Fixture Player"}
            """.utf8),
            forKey: SelectedPlayerIdentity.storageKey
        )
    }
    return FestivalSession(factory: { client }, selectionStorage: defaults)
}

/// Build a selected-profile session whose notification feed is already loaded.
///
/// The sheet's own `.task` refresh then revalidates without leaving the loaded
/// rows, so readiness never depends on when SwiftUI starts that task in an
/// offscreen host under a loaded parallel CI run (it once stayed on the spinner
/// for the whole settle timeout).
///
/// - Parameter transport: Fixture transport serving the feed.
/// - Returns: Session whose `notificationsCenter` is `.loaded`.
@MainActor
private func preloadedNotificationsSession(
    transport: HostedHistoryTransport
) async -> FestivalSession {
    let session = hostedHistorySession(transport: transport)
    await session.notificationsCenter.refresh(session: session)
    #expect(session.notificationsCenter.state == .loaded)
    return session
}

private let fixtureSong = Song(
    songId: "fixture-song", title: "Fixture Anthem", artist: "The Fixtures", album: nil,
    year: 2024, durationSeconds: 180, albumArt: nil, difficulty: nil,
    pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
)

// MARK: - Player History

/// Score history is a section of the song page: the selector, the chart and the best
/// scores (highest first, the best marked). With five or fewer scores there is no View
/// All Scores button (web `chartData.length > 5`).
@MainActor
@Test func songScoreHistorySectionRendersChartAndBestScores() async throws {
    let transport = HostedHistoryTransport()
    let session = hostedHistorySession(transport: transport)
    let payload = try await session.songHistory(accountId: "fixture-1", songId: "fixture-song")
    let entries = payload.response.history
    #expect(entries.count == 3)
    let size = CGSize(width: 420, height: 900)
    let host = nativeHostedView(
        ScrollView {
            SongScoreHistorySection(
                song: fixtureSong, entries: entries, pool: [.lead, .bass],
                instrument: .constant(nil)
            )
            .padding(16)
        }
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Score History", "score 850,000"])
    _ = try nativeHostedPNG(image, filename: "song-score-history.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["Score History", "score 850,000"],
        notContaining: ["View All Scores"]
    )
}

/// Issue #324: with more than five scores the section still lists only the best five and
/// ends with View All Scores (which opens the Score History page), never expanding in
/// place.
@MainActor
@Test func songScoreHistorySectionCapsAtFiveWithViewAllScores() async throws {
    let transport = HostedHistoryTransport()
    await transport.setExtraLeadScores([500_000, 400_000, 300_000])
    let session = hostedHistorySession(transport: transport)
    let entries = try await session.songHistory(accountId: "fixture-1", songId: "fixture-song").response.history
    #expect(entries.count == 6)
    let size = CGSize(width: 420, height: 1100)
    let host = nativeHostedView(
        NavigationStack {
            ScrollView {
                SongScoreHistorySection(
                    song: fixtureSong, entries: entries, pool: [.lead], instrument: .constant(nil)
                )
                .padding(16)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["score 400,000", "View All Scores"])
    assertRendersContent(
        host, image: image,
        containing: ["score 850,000", "score 400,000", "View All Scores, Lead Score History"],
        notContaining: ["score 300,000", "Show top scores"]
    )
}

/// Issue #32: Score History list rows show the season only when the page is at least
/// 520 pt wide (web `QUERY_SHOW_SEASON`); a portrait-phone page hides it.
@MainActor
@Test(arguments: [(393.0, false), (600.0, true)])
func songScoreHistoryRowsShowTheSeasonOnlyOnWidePages(width: Double, shows: Bool) async throws {
    let transport = HostedHistoryTransport()
    let session = hostedHistorySession(transport: transport)
    let entries = try await session.songHistory(accountId: "fixture-1", songId: "fixture-song").response.history
    let size = CGSize(width: width, height: 900)
    let host = nativeHostedView(
        ScrollView {
            SongScoreHistorySection(
                song: fixtureSong, entries: entries, pool: [.lead],
                instrument: .constant(nil),
                viewportWidth: size.width, currentSeason: 40
            )
            .padding(16)
        }
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["score 850,000", "score 700,000"])
    _ = try nativeHostedPNG(
        image, filename: "song-score-history-season-\(Int(width)).png", environment: "FST_HISTORY_RENDER_OUT"
    )
    let seasons = ["current season 40, score 850,000", "season 39, score 700,000"]
    if shows {
        assertRendersContent(host, image: image, containing: seasons)
    } else {
        assertRendersContent(host, image: image, containing: ["score 850,000"], notContaining: ["season 39", "season 40"])
    }
}

// MARK: - Score History page (issue #324)

/// Host the Score History page in a navigation stack.
///
/// - Parameters:
///   - session: Fixture session.
///   - instrument: Chart to show.
///   - size: Window size.
///   - besideList: The list page beside it in a split's trailing pane, or nil.
///   - dynamicTypeSize: Text size to lay the page out at.
/// - Returns: The hosting view.
@MainActor
private func hostedHistoryPage(
    _ session: FestivalSession, instrument: Instrument = .lead,
    size: CGSize = CGSize(width: 420, height: 900),
    besideList: OnDemandSplitPolicy.ListPage? = nil,
    dynamicTypeSize: DynamicTypeSize = .large
) -> NSHostingView<some View> {
    nativeHostedView(
        NavigationStack {
            PlayerHistoryScreen(session: session, song: fixtureSong, instrument: instrument)
                .splitPaneContext(besideList.map { SplitPaneContext(role: .trailing, besideList: $0) })
        }
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
}

/// Every score of the chart, Score descending by default (web `useSortedScoreHistory`),
/// the best one highlighted; Sort is offered and the song header names the chart.
@MainActor
@Test func playerHistoryScreenListsEveryScoreBestFirst() async throws {
    let transport = HostedHistoryTransport()
    await transport.setExtraLeadScores([500_000, 400_000, 300_000])
    let session = hostedHistorySession(transport: transport)
    let host = hostedHistoryPage(session, size: CGSize(width: 420, height: 1000))
    let window = nativeHostedWindow(host, size: CGSize(width: 420, height: 1000))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["score 850,000", "score 300,000"], timeout: .seconds(60)
    )
    _ = try nativeHostedPNG(image, filename: "player-history-page.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(
        host, image: image,
        containing: ["Fixture Anthem", "Lead · Score History", "score 850,000", "best score", "score 300,000"]
    )
    let tree = nativeHostedAccessibility(host)
    let order = [850_000, 700_000, 600_000, 500_000, 400_000, 300_000].map { score in
        tree.texts.firstIndex { $0.contains("score \(score.formatted())") } ?? -1
    }
    #expect(order == order.sorted() && !order.contains(-1), "Score descending: \(order)")
    #expect(tree.texts.filter { $0.contains("best score") }.count == 1)
    #expect(tree.identifiers.contains("fst.history"))
    #expect(tree.identifiers.contains("fst.history.row.5"))
}

/// Beside Song Detail in a split, Score History is titled by its chart and never
/// repeats the song's title or artist (owner-approved variant, #342).
@MainActor
@Test func playerHistoryScreenBesideSongDetailIsTitledByItsChart() async throws {
    let session = hostedHistorySession(transport: HostedHistoryTransport())
    let host = hostedHistoryPage(session, besideList: .songDetail)
    let window = nativeHostedWindow(host, size: CGSize(width: 420, height: 900))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["score 850,000"], timeout: .seconds(60))
    _ = try nativeHostedPNG(image, filename: "player-history-split-title.png", environment: "FST_HISTORY_RENDER_OUT")
    let tree = nativeHostedAccessibility(host)
    #expect(tree.identifiers.contains("fst.history.board-title"))
    #expect(!tree.identifiers.contains("fst.history.header"))
    #expect(tree.contains("Lead") && tree.contains("Score History"))
    #expect(!tree.contains("Fixture Anthem") && !tree.contains("The Fixtures"), "texts: \(tree.texts)")
}

/// The Score History page root (`fst.history`, issue #302) for assistive technology, on
/// the iPhone page and in a split's trailing pane beside Song Detail (iPad, Duo, Mac),
/// at standard and AX5 text (issue #385). The root is an unnamed container (an AppKit
/// group or the list itself here; a non-element container on iOS) holding the heading and
/// then each score row in score order, so VoiceOver never reads the page as one element;
/// every row is named, the best one says so, and nothing is left unnamed. Rows keep the
/// 44 pt minimum and, at AX5, stack, grow taller and stay inside the column: macOS
/// hosting keeps the font size (13 pt body), so a 160 pt page reproduces an iPhone 17 Pro
/// at AX5 (53 pt body, 342 pt of row content), as
/// `rankingsRowsFitANarrowColumnAtAccessibilitySizes` does. The one-line row overflowed it
/// and broke the score between digits: `scoreHistoryRowDrawsWholeNumbersAtAccessibilitySizes`
/// reads the drawn text back (macOS List rows do not draw into a hosted capture), and
/// `ScoreHistoryAccessibilityJourneyTests` proves the iOS and iPadOS AX5 metrics (53 pt
/// body) on device.
///
/// - Parameter besideSongDetail: Host the page in a split's trailing pane.
@MainActor
@Test(arguments: [false, true])
func playerHistoryScreenRootKeepsItsReadingOrder(besideSongDetail: Bool) async throws {
    let heading = besideSongDetail ? "fst.history.board-title" : "fst.history.header"
    let scores = ["score 850,000", "score 700,000", "score 600,000"]
    var rowHeights: [CGFloat] = []
    for (textSize, width) in [(DynamicTypeSize.large, CGFloat(420)), (.accessibility5, 160)] {
        let name = "history-\(besideSongDetail ? "split" : "page")-\(textSize)"
        let size = CGSize(width: width, height: 1400)
        let host = hostedHistoryPage(
            hostedHistorySession(transport: HostedHistoryTransport()), size: size,
            besideList: besideSongDetail ? .songDetail : nil, dynamicTypeSize: textSize
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host, untilText: scores, timeout: .seconds(60))
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: name)

        let root = try #require(nodes.firstIndex { $0.identifier == "fst.history" }, "\(name): no page root")
        #expect(
            ["AXGroup", "AXOutline"].contains(nodes[root].role) && nodes[root].spokenName.isEmpty,
            "\(name): the page root is an unnamed container: \(nodes[root])"
        )
        #expect(!nodes.contains { $0.identifier == "fst.score-history.page" }, "\(name): unregistered root")
        let pageEnd = nodes[(root + 1)...].firstIndex { $0.depth <= nodes[root].depth } ?? nodes.endIndex

        let title = try #require(nodes.firstIndex { $0.identifier == heading && $0.isElement }, "\(name): no heading")
        #expect(nodes[title].role == "AXHeading", "\(name): the title is a heading: \(nodes[title])")
        #expect(nodes[title].spokenName.contains("Score History"), "\(name): \(nodes[title])")
        let rows = try scores.indices.map { index in
            try #require(
                nodes.firstIndex { $0.identifier == "fst.history.row.\(index)" && $0.isElement },
                "\(name): row \(index) is not an element"
            )
        }
        #expect(([title] + rows).allSatisfy { $0 > root && $0 < pageEnd }, "\(name): content outside the page root")
        #expect([title] + rows == ([title] + rows).sorted(), "\(name): heading, then rows: \(title) \(rows)")
        for (row, score) in zip(rows, scores) {
            #expect(nodes[row].spokenName.contains(score), "\(name): \(nodes[row])")
        }
        #expect(nodes[rows[0]].spokenName.contains("best score"), "\(name): \(nodes[rows[0]])")
        #expect(macAccessibilityFindings(nodes.filter(\.isElement)) == [], "\(name)")

        let frame = try #require(nativeHostedAccessibilityFrame("fst.history.row.0", in: host))
        #expect(frame.height >= 44 && frame.minX >= 0 && frame.maxX <= width, "\(name): row frame \(frame)")
        rowHeights.append(frame.height)
    }
    #expect(rowHeights[1] > rowHeights[0], "AX5 rows grow with the text: \(rowHeights)")
}

/// The digits of the score and accuracy a Score History row's spoken label names
/// ("…, score 850,000, accuracy 99.1 percent, …" → ["850000", "991"]).
///
/// - Parameter label: The row's accessibility label.
/// - Returns: The score's digits, then the accuracy's when the row has one.
func scoreHistoryDrawnNumbers(_ label: String) -> [String] {
    ["score ", "accuracy "].compactMap { key in
        guard let start = label.range(of: key)?.upperBound else { return nil }
        let value = label[start...].prefix { $0 != " " }
        let digits = nativeHostedDigits(String(value))
        return digits.isEmpty ? nil : digits
    }
}

/// The shared Score History row draws its score and accuracy whole, each on one line, at
/// the standard size and at AX5 in a column as narrow as an iPhone 17 Pro's at AX5 (13 pt
/// macOS body in 160 pt; issue #385). The one-line row kept its label and frame valid but
/// broke "850,000" between digits; only the drawn text shows that, so the row is hosted
/// on its own (a macOS List row does not draw into a hosted capture) and read back with
/// text recognition (Vision). Standard rows stay one line; AX5 rows stack and grow.
@MainActor
@Test func scoreHistoryRowDrawsWholeNumbersAtAccessibilitySizes() async throws {
    let json = Data("""
        [{"songId":"fixture-anthem","instrument":"Solo_Guitar","oldScore":700000,"newScore":850000,
          "oldRank":9,"newRank":4,"accuracy":991200,"isFullCombo":true,"season":40,
          "scoreAchievedAt":"2026-02-08T00:00:00Z","changedAt":"2026-02-08T00:00:00Z"},
         {"songId":"fixture-anthem","instrument":"Solo_Guitar","oldScore":null,"newScore":700000,
          "oldRank":null,"newRank":9,"accuracy":954500,"isFullCombo":false,"season":39,
          "scoreAchievedAt":"2026-01-08T00:00:00Z","changedAt":"2026-01-08T00:00:00Z"}]
        """.utf8)
    let entries = try JSONDecoder().decode([ScoreHistoryEntry].self, from: json)
    var heights: [CGFloat] = []
    for (textSize, width) in [(DynamicTypeSize.large, CGFloat(420)), (.accessibility5, 160)] {
        let name = "history-row-\(textSize)"
        let size = CGSize(width: width, height: 600)
        let host = nativeHostedView(
            VStack(spacing: 8) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    ScoreHistoryListRow(entry: entry, isBest: index == 0)
                        .accessibilityIdentifier("fst.history.row.\(index)")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .environment(\.dynamicTypeSize, textSize)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(host, untilText: ["score 850,000", "score 700,000"])
        _ = try nativeHostedPNG(image, filename: "\(name).png", environment: "FST_HISTORY_RENDER_OUT")
        let tree = macAccessibilityTree(host)
        for index in entries.indices {
            let id = "fst.history.row.\(index)"
            let label = try #require(tree.first { $0.identifier == id && $0.isElement }, "\(name): \(id)").spokenName
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: host), "\(name): \(id) frame")
            #expect(frame.height >= 44 && frame.minX >= 0 && frame.maxX <= width, "\(name): \(id) \(frame)")
            let recognized = nativeHostedRecognizedText(try nativeHostedImage(host, in: frame))
            let lines = recognized.lines
            let numbers = scoreHistoryDrawnNumbers(label)
            #expect(numbers.count == 2, "\(name): score and accuracy in \(label)")
            if lines.isEmpty, nativeHostedIsVirtualMachine, case let probe = try nativeHostedTextRecognitionProbe(),
               !probe.available {
                // Vision reads nothing in this VM (not even the probe's large text), so the drawn
                // text cannot be judged here; the label and frame checks above still hold, and a
                // real Mac (or the iOS/iPadOS journeys) judges it strictly.
                withKnownIssue("Vision reads no text on this host: \(probe.attempts); row: \(recognized.attempts)") {
                    Issue.record("\(name): \(id) drawn text not recognized")
                }
                if index == 0 { heights.append(frame.height) }
                continue
            }
            for digits in numbers {
                #expect(
                    lines.contains { nativeHostedDigits($0).contains(digits) },
                    "\(name): \(id) draws \(digits) whole on one line: \(lines) (\(recognized.attempts))"
                )
            }
            #expect(!lines.contains { $0.contains("\u{2026}") }, "\(name): \(id) is truncated: \(lines)")
            if index == 0 { heights.append(frame.height) }
        }
    }
    #expect(heights[1] > heights[0], "AX5 rows stack and grow: \(heights)")
}

/// A chart without scores reads the web's empty copy.
@MainActor
@Test func playerHistoryScreenShowsEmptyInstrument() async throws {
    let session = hostedHistorySession(transport: HostedHistoryTransport())
    let host = hostedHistoryPage(session, instrument: .drums)
    let window = nativeHostedWindow(host, size: CGSize(width: 420, height: 900))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["No score history for this instrument."])
    assertRendersContent(host, image: image, containing: ["No Score History"], notContaining: ["score 850,000"])
}

/// 202: the history is still syncing (web `PlayerHistoryPage` syncing state).
@MainActor
@Test func playerHistoryScreenShowsSyncing() async throws {
    let transport = HostedHistoryTransport()
    await transport.setHistoryStatus(202)
    let session = hostedHistorySession(transport: transport)
    let host = hostedHistoryPage(session)
    let window = nativeHostedWindow(host, size: CGSize(width: 420, height: 900))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["History Is Syncing"])
    assertRendersContent(host, image: image, containing: ["still syncing"])
}

/// 404: only registered users have score history.
@MainActor
@Test func playerHistoryScreenShowsUnregistered() async throws {
    let session = hostedHistorySession(transport: HostedHistoryTransport(), accountId: "fixture-unregistered")
    let host = hostedHistoryPage(session)
    let window = nativeHostedWindow(host, size: CGSize(width: 420, height: 900))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["only available for registered users"])
    // Unavailable, not a no-results empty state: it keeps Retry (empty-error-states R1, R8).
    assertRendersContent(host, image: image, containing: ["History Unavailable", "Retry"])
    #expect(nativeHostedAccessibility(host).identifiers.contains("fst.service-status.retry"))
}

/// No selected player: the web's "Select a player" message with Choose Profile.
@MainActor
@Test func playerHistoryScreenAsksForAPlayer() async throws {
    let session = hostedHistorySession(transport: HostedHistoryTransport(), accountId: nil)
    let host = hostedHistoryPage(session)
    let window = nativeHostedWindow(host, size: CGSize(width: 420, height: 900))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Select a player to view score history."])
    assertRendersContent(host, image: image, containing: ["Choose Profile", "Fixture Anthem"])
}

/// The sort sheet offers the web's four modes, the direction control with the web's
/// score-history copy and the red Reset.
@MainActor
@Test func playerHistorySortSheetOffersTheWebModes() async throws {
    let size = CGSize(width: 400, height: 640)
    let host = nativeHostedView(
        PlayerHistorySortSheet(mode: .score, ascending: false) { _, _ in }
            .environment(\.festivalModalPreview, true)
            .formStyle(.grouped)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Reset Sort Settings", "Newest first, high to low"])
    assertRendersContent(
        host, image: image,
        containing: ["Date", "Score", "Accuracy", "Season", "Sort Direction", "Descending"]
    )
    let ids = nativeHostedAccessibility(host).identifiers
    #expect(ids.contains("fst.history.sort.direction.ascending"))
    #expect(ids.contains("fst.history.sort.reset"))
}

/// Issue #32: a top-score row draws the season pill only when its card turns the
/// column on, and an entry without a season keeps the slot without speaking it.
@MainActor
@Test func songLeaderboardEntryRowSeasonColumnFollowsTheCard() async throws {
    func entry(_ id: String, season: Int?) -> LeaderboardEntry {
        LeaderboardEntry(
            accountId: id, displayName: "Fixture \(id)", score: 99_800, rank: 2, localRank: nil,
            accuracy: 980_000, isFullCombo: false, stars: 5, season: season, difficulty: 3
        )
    }
    let size = CGSize(width: 600, height: 200)
    let host = nativeHostedView(
        VStack(spacing: 8) {
            SongLeaderboardEntryRow(entry: entry("a", season: 9), seasonColumn: true, currentSeason: 9)
            SongLeaderboardEntryRow(entry: entry("b", season: 8), seasonColumn: true, currentSeason: 9)
            SongLeaderboardEntryRow(entry: entry("c", season: nil), seasonColumn: true)
            SongLeaderboardEntryRow(entry: entry("d", season: 7))
        }
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Current season 9", "Season 8", "Fixture d"])
    assertRendersContent(
        host, image: image, containing: ["Current season 9", "Season 8"], notContaining: ["Season 7"]
    )
}

// MARK: - Notifications

@MainActor
@Test func notificationsSheetRendersRowsWithUnreadSection() async throws {
    let transport = HostedHistoryTransport()
    let session = await preloadedNotificationsSession(transport: transport)
    let size = CGSize(width: 420, height: 700)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["You climbed from #42 to #10 on Lead", "Full Combo on Bass", "Drums: First Play"]
    )
    _ = try nativeHostedPNG(image, filename: "notifications.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["You climbed from #42 to #10 on Lead", "Full Combo on Bass", "Drums: First Play"]
    )
}

/// No selected profile shows "Choose a Profile" rather than an empty feed
/// (`notifications` control's `no-profile` state).
@MainActor
@Test func notificationsSheetRendersNoProfileState() async throws {
    let transport = HostedHistoryTransport()
    // A session with no stored selection at all: `selectedPlayer` is nil.
    let client = try! FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    let session = FestivalSession(factory: { client })
    #expect(session.selectedPlayer == nil)
    let size = CGSize(width: 420, height: 500)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Choose a Profile"])
    _ = try nativeHostedPNG(image, filename: "notifications-no-profile.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Choose a Profile"])
}

/// A generated-but-empty feed shows the "will appear here" copy
/// (`notifications` control's `empty-generated` state).
@MainActor
@Test func notificationsSheetRendersEmptyGeneratedState() async throws {
    let transport = HostedHistoryTransport()
    await transport.setNotificationsBody(Data("""
    {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":1,
     "sourceCompletedAt":"2024-01-05T00:00:00Z","notificationsGenerated":true,"items":[]}
    """.utf8))
    let session = await preloadedNotificationsSession(transport: transport)
    let size = CGSize(width: 420, height: 500)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["No notifications available", "will appear here when new high scores are set"]
    )
    _ = try nativeHostedPNG(
        image, filename: "notifications-empty-generated.png", environment: "FST_HISTORY_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image,
        containing: ["No notifications available", "will appear here when new high scores are set"]
    )
}

/// A feed that has never been generated shows the "may appear after the next
/// leaderboard update" copy (`notifications` control's `empty-not-generated` state).
@MainActor
@Test func notificationsSheetRendersEmptyNotGeneratedState() async throws {
    let transport = HostedHistoryTransport()
    await transport.setNotificationsBody(Data("""
    {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":null,
     "sourceCompletedAt":null,"notificationsGenerated":false,"items":[]}
    """.utf8))
    let session = await preloadedNotificationsSession(transport: transport)
    let size = CGSize(width: 420, height: 500)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["No notifications available", "may appear here after the next leaderboard update"]
    )
    _ = try nativeHostedPNG(
        image, filename: "notifications-empty-not-generated.png", environment: "FST_HISTORY_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image,
        containing: ["No notifications available", "may appear here after the next leaderboard update"]
    )
}
#endif
