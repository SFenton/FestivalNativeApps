#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixture transport

/// Keyless fixture transport for two long band boards with no selected player (issue
/// #305): a 60-team Band Rankings board and a 60-band Song Band leaderboard, 25 rows a
/// page so each page scrolls behind its pager. Rejects the privileged key,
/// selected-profile headers, writes and any other route.
actor LongBandBoardsTransport: HTTPTransport {
    private let generation = 23
    static let songId = "fade-song"
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
        if url.path == "/api/songs" {
            return HTTPResult(status: 200, data: Data("""
            {"count":1,"currentSeason":40,"songs":[
              {"songId":"\(Self.songId)","title":"Fade Anthem","artist":"The Fixtures",
               "album":null,"year":2024,"durationSeconds":180,"albumArt":null,
               "difficulty":null,"pathArtifactGenerationId":null}
            ]}
            """.utf8), headers: pinned)
        }
        if parts.count == 5, parts[1] == "api", parts[2] == "rankings", parts[3] == "bands" {
            return HTTPResult(status: 200, data: try bandRankingsBody(bandType: parts[4], url: url), headers: pinned)
        }
        if parts.count == 6, parts[1] == "api", parts[2] == "leaderboard", parts[3] == Self.songId, parts[4] == "bands" {
            return HTTPResult(status: 200, data: try songBandBody(bandType: parts[5], url: url), headers: pinned)
        }
        throw FestivalAPIError.httpStatus(404)
    }

    private func query(_ url: URL) -> [String: String] {
        Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func bandRankingsBody(bandType: String, url: URL) throws -> Data {
        let query = query(url)
        let page = Int(query["page"] ?? "1") ?? 1
        let pageSize = Int(query["pageSize"] ?? "25") ?? 25
        let first = (page - 1) * pageSize + 1
        let entries: [[String: Any]] = (first..<min(first + pageSize, Self.total + 1)).map { rank in
            [
                "bandId": "fade-band-\(rank)", "teamKey": "fade-team-\(rank)",
                "teamMembers": [
                    ["accountId": "fade-member-\(rank)a", "displayName": "Member \(rank)A"],
                    ["accountId": "fade-member-\(rank)b", "displayName": "Member \(rank)B"],
                ],
                "songsPlayed": 30, "totalChartedSongs": 50, "coverage": 0.6,
                "rawSkillRating": 0.02, "adjustedSkillRating": 0.02, "adjustedSkillRank": rank,
                "weightedRating": 0.03, "weightedRank": rank, "fcRate": 0.4, "fcRateRank": rank,
                "totalScore": 50_000_000 - rank * 1000, "totalScoreRank": rank,
                "avgAccuracy": 0.95, "fullComboCount": 10, "avgStars": 4.5, "bestRank": 1, "avgRank": 3.1,
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "bandType": bandType, "rankBy": query["rankBy"] ?? "totalscore", "page": page,
            "pageSize": pageSize, "totalTeams": Self.total, "entries": entries,
        ] as [String: Any])
    }

    private func songBandBody(bandType: String, url: URL) throws -> Data {
        let query = query(url)
        let top = Int(query["top"] ?? "25") ?? 25
        let offset = Int(query["offset"] ?? "0") ?? 0
        let entries: [[String: Any]] = ((offset + 1)..<min(offset + top + 1, Self.total + 1)).map { rank in
            [
                "bandId": "fade-band-\(rank)", "bandType": bandType, "teamKey": "fade-team-\(rank)",
                "comboId": NSNull(),
                "members": [
                    ["accountId": "fade-band-\(rank)-a", "displayName": "Band \(rank) Member A",
                     "instruments": ["Solo_Guitar"], "score": 95_000 - rank * 500, "accuracy": 970_000,
                     "isFullCombo": false, "stars": 5, "difficulty": 4, "season": 10],
                    ["accountId": "fade-band-\(rank)-b", "displayName": "Band \(rank) Member B",
                     "instruments": ["Solo_Bass"], "score": 94_500 - rank * 500, "accuracy": 960_000,
                     "isFullCombo": false, "stars": 5, "difficulty": 4, "season": 10],
                ],
                "score": 95_000 - rank * 500, "rank": rank, "accuracy": 965_000, "isFullCombo": false,
                "stars": 5, "season": 10, "difficulty": 4, "percentile": 0.01 * Double(rank), "endTime": NSNull(),
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "songId": Self.songId, "bandType": bandType, "count": entries.count,
            "totalEntries": Self.total, "localEntries": Self.total, "entries": entries,
        ] as [String: Any])
    }
}

// MARK: - Hosting

/// Accessibility settings a capture renders with: none, or one of the four that make
/// the fade a hard edge (scroll-edge R7).
enum BottomChromeFadeMode: String, CaseIterable, CustomTestStringConvertible {
    case standard, systemReduceTransparency, systemIncreaseContrast, lessTransparency, moreContrast

    var testDescription: String { rawValue }

    /// Whether this mode expects a hard edge rather than a fade.
    var hardEdge: Bool { self != .standard }

    /// A fresh defaults suite with the app's Reduce Motion on (load-in fades never
    /// advance offscreen) and this mode's in-app accessibility setting.
    func storage() -> (UserDefaults, String) {
        let suite = "fst.tests.bottom-chrome-fade.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "fst.accessibility.reduceMotion")
        switch self {
        case .lessTransparency: defaults.set(true, forKey: "fst.accessibility.lessTransparency")
        case .moreContrast: defaults.set(true, forKey: "fst.accessibility.moreContrast")
        default: break
        }
        return (defaults, suite)
    }

    /// `content` with this mode's system setting. The host does not force its glass
    /// fallback (system Reduce Transparency), which would make every mode a hard edge.
    func system(_ content: some View) -> some View {
        content
            .environment(\._accessibilityReduceTransparency, self == .systemReduceTransparency)
            .environment(\._colorSchemeContrast, self == .systemIncreaseContrast ? .increased : .standard)
    }
}

/// The board's own scroll view: the deepest one whose content runs past its height.
@MainActor
private func boardScrollView(in view: NSView) -> NSScrollView? {
    for subview in view.subviews {
        if let found = boardScrollView(in: subview) { return found }
    }
    if let scroll = view as? NSScrollView, let document = scroll.documentView,
       document.frame.height > scroll.contentView.bounds.height + 100 {
        return scroll
    }
    return nil
}

// MARK: - Journey

/// Mean channel value (0–255) above which a sample is row text: the rows' light grey
/// text measures ~140 on cards of ~35. Within 10 pt of the chrome the fade leaves text
/// at most ~28% opaque (~65), well under it.
private let rowTextThreshold = 100

/// The two band boards, each with its row identifiers.
enum BottomChromeBandBoard: String, CaseIterable, CustomTestStringConvertible {
    case bandRankings, songBand

    var testDescription: String { rawValue }

    /// Accessibility identifier of the row at `rank` (1-based, page 1).
    func rowId(_ rank: Int) -> String {
        switch self {
        case .bandRankings: "fst.band-rankings.row.fade-team-\(rank)"
        case .songBand: "fst.song-band-leaderboard.row.fade-band-\(rank):\(rank)"
        }
    }

    /// Text the first page shows once loaded.
    var loadedText: String {
        switch self {
        case .bandRankings: "Member 1A"
        case .songBand: "Band 1 Member A"
        }
    }

    @MainActor
    func screen(_ session: FestivalSession) async throws -> AnyView {
        switch self {
        case .bandRankings:
            return AnyView(BandRankingsScreen(session: session, bandType: "Band_Duets"))
        case .songBand:
            let song = try #require(try await session.catalog().catalog.songs.first {
                $0.songId == LongBandBoardsTransport.songId
            })
            return AnyView(SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets"))
        }
    }
}

/// Scroll the board's clip view so `offset` points of content sit above its top, and
/// let the scroll-driven fade height and mask settle.
@MainActor
private func scrollBoard(
    _ scroll: NSScrollView, to offset: CGFloat, host: NSHostingView<some View>
) async throws -> CGImage {
    let clip = scroll.contentView
    clip.scroll(to: NSPoint(x: 0, y: offset - scroll.contentInsets.top))
    scroll.reflectScrolledClipView(clip)
    return try await nativeHostedSettle(host)
}

/// Issue #305: a band board with no player footer scrolls its rows into a 40 pt fade (issue #329)
/// above the pinned pager, not a hard cut at (Song Band, whose pager used to sit below
/// the scroll view) or a leak under it (Band Rankings, which had no mask); at the end
/// the last row rests fully drawn above the pager. System Reduce Transparency and
/// Increase Contrast, and the app's Less Transparency and Increase Contrast, each make
/// the fade a hard edge instead (scroll-edge R7).
///
/// Bright samples (row text) are counted in a 9 pt strip 1–10 pt above the chrome's top
/// at 6 mid-list offsets 9 pt apart, one 54 pt row pitch with no gaps between strip
/// positions, so every line of row text crosses the strip: with the fade it stays dim (at most 25% opacity there);
/// with a hard edge it shows at full brightness.
@MainActor
@Test(.serialized, arguments: BottomChromeBandBoard.allCases, BottomChromeFadeMode.allCases)
func bandBoardRowsFadeAbovePagerWithoutPlayerFooter(board: BottomChromeBandBoard, mode: BottomChromeFadeMode) async throws {
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongBandBoardsTransport())
    let session = FestivalSession(factory: { client })
    #expect(session.selectedPlayer == nil)
    let (defaults, suite) = mode.storage()
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let size = CGSize(width: 402, height: 700)
    let host = nativeHostedView(
        mode.system(
            try await board.screen(session)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .defaultAppStorage(defaults)
        ),
        size: size, forceGlassFallback: false
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: [board.loadedText], timeout: .seconds(60))
    let scroll = try #require(boardScrollView(in: host))
    let scrollFrame = scroll.convert(scroll.bounds, to: host)
    #expect(host.isFlipped)
    // The pinned pager is the scroll view's bottom inset; nothing else sits there.
    #expect(scroll.contentInsets.bottom > 30)
    let chromeTop = scrollFrame.maxY - scroll.contentInsets.bottom
    let near = CGRect(x: 0, y: chromeTop - 10, width: size.width, height: 9)
    let far = CGRect(x: 0, y: chromeTop - 160, width: size.width, height: 120)

    var nearBright = 0
    for step in 0..<6 {
        let image = try await scrollBoard(scroll, to: 300 + CGFloat(step) * 9, host: host)
        if step == 0 {
            _ = try nativeHostedPNG(
                image, filename: "\(board.rawValue)-mid-\(mode.rawValue).png", environment: "FST_LEADERBOARDS_RENDER_OUT"
            )
        }
        #expect(nativeHostedBrightSamples(in: far, of: image, hostSize: size, threshold: rowTextThreshold) > 0, "rows above the fade are drawn")
        nearBright += nativeHostedBrightSamples(in: near, of: image, hostSize: size, threshold: rowTextThreshold)
    }
    if !mode.hardEdge {
        #expect(nearBright == 0, "row text fades out above the pager")
    } else {
        #expect(nearBright > 0, "a hard edge draws rows fully up to the pager")
    }

    // End of the page: the last row rests above the pager, unfaded in every mode.
    let document = try #require(scroll.documentView)
    let end = document.frame.height + scroll.contentInsets.bottom - scroll.contentView.bounds.height
        + scroll.contentInsets.top
    let image = try await scrollBoard(scroll, to: end, host: host)
    _ = try nativeHostedPNG(
        image, filename: "\(board.rawValue)-end-\(mode.rawValue).png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    let last = try #require(nativeHostedAccessibilityFrame(board.rowId(25), in: host))
    let previous = try #require(nativeHostedAccessibilityFrame(board.rowId(24), in: host))
    #expect(last.maxY <= chromeTop + 0.5, "the last row is not under the pager")
    #expect(last.maxY >= chromeTop - 12, "the last row rests just above the pager")
    let lastBright = nativeHostedBrightSamples(in: last, of: image, hostSize: size, threshold: rowTextThreshold)
    let previousBright = nativeHostedBrightSamples(in: previous, of: image, hostSize: size, threshold: rowTextThreshold)
    #expect(previousBright > 0)
    #expect(Double(lastBright) >= Double(previousBright) * 0.85, "the last row is as readable as the one above it")
}

// MARK: - Accessibility (issue #473, for #329)

/// One realized accessibility element: identifier, spoken text, role, state and frame.
private struct BoardAccessibilityNode {
    let identifier: String
    /// Label, then value, joined (what VoiceOver reads first).
    let text: String
    /// `AXRole` (`AXButton` for a row or a pager arrow).
    let role: String
    /// `AXEnabled`: false for a disabled pager arrow.
    let enabled: Bool
    /// `AXSelected`: the Mac keyboard highlight (`MacKeyboardNavigation`).
    let selected: Bool
    /// Frame in the host's top-left points, if the element has one.
    let frame: CGRect?

    /// Whether the element is a button.
    var isButton: Bool { role == NSAccessibility.Role.button.rawValue }
}

/// Every realized element under `host` that carries an identifier or spoken text, in
/// accessibility tree order (accessibility children, then AppKit subviews).
///
/// - Parameter host: The window's hosting view.
/// - Returns: The elements, depth first.
@MainActor
private func boardAccessibilityNodes(in host: NSView) -> [BoardAccessibilityNode] {
    var nodes: [BoardAccessibilityNode] = []
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func walk(_ node: Any, depth: Int) {
        guard depth < 80, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return }
        let identifier = nativeHostedAccessibilityString(object, "accessibilityIdentifier")
        let text = [
            nativeHostedAccessibilityString(object, "accessibilityLabel"),
            nativeHostedAccessibilityString(object, "accessibilityValue"),
        ].filter { !$0.isEmpty }.joined(separator: ", ")
        if !identifier.isEmpty || !text.isEmpty {
            nodes.append(BoardAccessibilityNode(
                identifier: identifier, text: text,
                role: (read(object, "accessibilityRole") as? String) ?? "",
                enabled: (read(object, "isAccessibilityEnabled") as? Bool) ?? true,
                selected: (read(object, "isAccessibilitySelected") as? Bool) ?? false,
                frame: nativeHostedAccessibilityFrame(of: object, in: host)
            ))
        }
        for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, depth: depth + 1)
        }
        if let view = object as? NSView {
            for subview in view.subviews { walk(subview, depth: depth + 1) }
        }
    }
    walk(host, depth: 0)
    return nodes
}

extension BottomChromeBandBoard {
    /// Identifier prefix of the board's pager controls (`<prefix>.page-first` …).
    var pagerPrefix: String {
        switch self {
        case .bandRankings: "fst.band-rankings"
        case .songBand: "fst.song-band-leaderboard"
        }
    }

    /// Text a row at `rank` speaks (its first member's name).
    func rowText(_ rank: Int) -> String {
        switch self {
        case .bandRankings: "Member \(rank)A"
        case .songBand: "Band \(rank) Member A"
        }
    }

    /// Rank of the page-1 row `identifier` names, if it is one.
    func rank(of identifier: String) -> Int? {
        (1...LongBandBoardsTransport.total).first { rowId($0) == identifier }
    }

    /// The pager's arrows with the word each name carries and whether page 1 enables it.
    static let pagerArrows = [
        (suffix: "page-first", word: "First", enabledOnFirstPage: false),
        (suffix: "page-previous", word: "Previous", enabledOnFirstPage: false),
        (suffix: "page-next", word: "Next", enabledOnFirstPage: true),
        (suffix: "page-last", word: "Last", enabledOnFirstPage: true),
    ]
}

/// The board as the app hosts it: inside a navigation stack (its rows are links, which
/// report themselves disabled without one).
///
/// - Parameters:
///   - board: The board.
///   - session: Its session.
/// - Returns: The screen in a `NavigationStack`.
@MainActor
private func stackedBoard(_ board: BottomChromeBandBoard, session: FestivalSession) async throws -> some View {
    let screen = try await board.screen(session)
    return NavigationStack { screen }
}

/// Require page 1's pager arrows to be named, enabled-state-correct, 44 pt buttons below
/// the fade's chrome top.
///
/// - Parameters:
///   - nodes: The realized elements.
///   - board: The board.
///   - chromeTop: The pager's top edge (the fade's bottom).
@MainActor
private func expectFirstPagePager(
    _ nodes: [BoardAccessibilityNode], board: BottomChromeBandBoard, chromeTop: CGFloat
) throws {
    for arrow in BottomChromeBandBoard.pagerArrows {
        let control = try #require(nodes.first { $0.identifier == "\(board.pagerPrefix).\(arrow.suffix)" })
        #expect(control.isButton, "\(arrow.suffix) is a button: \(control.role)")
        #expect(control.enabled == arrow.enabledOnFirstPage, "\(arrow.suffix) enabled on page 1: \(control.enabled)")
        #expect(control.text.localizedCaseInsensitiveContains(arrow.word), "\(arrow.suffix) reads \(control.text)")
        let frame = try #require(control.frame)
        #expect(frame.width >= 44 && frame.height >= 44, "\(arrow.suffix) target \(frame)")
        #expect(frame.minY >= chromeTop - 0.5, "\(arrow.suffix) sits below the fade: \(frame) vs \(chromeTop)")
    }
}

/// Issue #473 (accessibility for #329's 40 pt board footer fade): the fade is drawing
/// only. Mid-scroll, every row inside the 40 pt band above the pager stays one named
/// element (its members, as at rest), and the mask adds nothing VoiceOver or Voice
/// Control can reach there. Rows read in rank order and before the pager, whose five
/// controls keep their spoken names and 44 pt targets (HIG Accessibility: iOS, iPadOS
/// default control size 44×44 pt) wholly below the fade, so the deeper ramp never dims
/// or covers a control. The same holds with the scroll-edge R7 hard edge (the app's
/// Increase Contrast). Rows stay enabled buttons in the band; the pager's arrows are
/// buttons enabled only where they can move. This SwiftUI is the same on iPhone, iPad,
/// iPhone Duo and Mac; `BoardFooterFadeJourneyTests` checks it at AX5 on iOS.
@MainActor
@Test(.serialized, arguments: BottomChromeBandBoard.allCases, [BottomChromeFadeMode.standard, .moreContrast])
func bandBoardFooterFadeKeepsRowsAndPagerAccessible(
    board: BottomChromeBandBoard, mode: BottomChromeFadeMode
) async throws {
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongBandBoardsTransport())
    let session = FestivalSession(factory: { client })
    let (defaults, suite) = mode.storage()
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let size = CGSize(width: 402, height: 700)
    let host = nativeHostedView(
        mode.system(
            try await stackedBoard(board, session: session)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .defaultAppStorage(defaults)
        ),
        size: size, forceGlassFallback: false
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: [board.loadedText], timeout: .seconds(60))
    let scroll = try #require(boardScrollView(in: host))
    let scrollFrame = scroll.convert(scroll.bounds, to: host)
    let chromeTop = scrollFrame.maxY - scroll.contentInsets.bottom
    let fadeBand = CGRect(
        x: 0, y: chromeTop - ScrollEdgeFade.distance, width: size.width, height: ScrollEdgeFade.distance
    )

    // Several mid-list offsets, so a row edge, a row middle and a gap each cross the band.
    for offset in stride(from: 300.0, through: 345.0, by: 15.0) {
        _ = try await scrollBoard(scroll, to: offset, host: host)
        let nodes = boardAccessibilityNodes(in: host)
        let rows = nodes.compactMap { node -> (rank: Int, node: BoardAccessibilityNode)? in
            board.rank(of: node.identifier).map { ($0, node) }
        }

        // Name: each row in the fade band is still one element reading its own members.
        let faded = rows.filter { $0.node.frame?.intersects(fadeBand) == true }
        #expect(!faded.isEmpty, "a row crosses the 40 pt fade band at offset \(offset)")
        for row in faded {
            #expect(row.node.text.contains(board.rowText(row.rank)), "row \(row.rank) in the fade reads \(row.node.text)")
            #expect(row.node.isButton, "row \(row.rank) in the fade is a button: \(row.node.role)")
            #expect(row.node.enabled, "row \(row.rank) in the fade is enabled")
            #expect((row.node.frame?.height ?? 0) >= 44, "row \(row.rank) keeps a 44 pt target in the fade")
        }

        // Nothing else in the band: the mask is decorative and hidden.
        let rowFrames = rows.compactMap(\.node.frame)
        let strays = nodes.filter { node in
            guard let frame = node.frame, frame.intersects(fadeBand), frame.height < size.height / 2,
                  board.rank(of: node.identifier) == nil,
                  !node.identifier.hasPrefix("\(board.pagerPrefix).page") else { return false }
            return !rowFrames.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) }
        }
        #expect(strays.isEmpty, "only rows are reachable in the fade band: \(strays.map { "\($0.identifier) \($0.text)" })")

        // Reading order: rows in rank order, then the pager.
        let ranks = rows.map(\.rank)
        #expect(ranks == ranks.sorted(), "rows read in rank order: \(ranks)")
        let pagerIndex = try #require(nodes.firstIndex { $0.identifier == "\(board.pagerPrefix).page-first" })
        let lastRowIndex = try #require(nodes.lastIndex { board.rank(of: $0.identifier) != nil })
        #expect(lastRowIndex < pagerIndex, "every row reads before the pager")

        // Pager: named buttons in their page-1 states, 44 pt, wholly below the fade;
        // the badge reads the page.
        try expectFirstPagePager(nodes, board: board, chromeTop: chromeTop)
        let info = try #require(nodes.first { $0.identifier == "\(board.pagerPrefix).page-info" })
        #expect(info.text.localizedCaseInsensitiveContains("Page"), "page-info reads \(info.text)")
        let infoFrame = try #require(info.frame)
        #expect(infoFrame.width >= 44 && infoFrame.height >= 44, "page-info target \(infoFrame)")
        #expect(infoFrame.minY >= chromeTop - 0.5, "page-info sits below the fade: \(infoFrame) vs \(chromeTop)")
    }
}

/// Deliver a key press (`MacDebugHooks.keyEvent(named:)`) through the window, as AppKit does.
///
/// - Parameters:
///   - name: Key name (`down`, `end`, `return` …).
///   - window: A titled window (a borderless one never becomes key).
@MainActor
private func sendBoardKey(_ name: String, to window: NSWindow) {
    guard let key = MacDebugHooks.keyEvent(named: name) else { return }
    let flags: NSEvent.ModifierFlags = key.keyCode >= 115 ? [.function, .numericPad] : []
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        if let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: key.characters,
            charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.keyCode
        ) {
            window.sendEvent(event)
        }
    }
}

/// Routes a hosted page pushed with Return.
@MainActor
private final class BoardKeyPushRecorder {
    var pushed: [AppRoute] = []
}

/// Issue #473 (keyboard, for #329's board footer fade): on the Mac the board is one
/// focus stop whose ↓/End move a highlight (`MacKeyboardNavigation`, macos.md keyboard
/// navigation). ↓ from the last row wholly above the fade moves the highlight row by row
/// past the fold: each highlighted row is scrolled into view and rests wholly above the
/// pager, never under it (WCAG 2.4.11 Focus Not Obscured, the Windows #409 rule); End
/// reaches the last row of the page above the pager, and Return opens it. The pager keeps
/// its page-1 button states and stays below the fade throughout. Tab from the board to
/// the pager's buttons is Full Keyboard Access ("Keyboard navigation"), a global system
/// setting a test must not turn on (macos.md open gaps). Forcing it in-process does not
/// help: with `isFullKeyboardAccessEnabled` and `AppleKeyboardUIMode` reading on, a hosted
/// window's key-view loop (`selectNextKeyView`) reaches a text field but never a SwiftUI
/// button (issue #473 probes), so that walk is an operator check. The arrows' button role
/// and enabled state, asserted here, are what it reaches.
@MainActor
@Test func bandBoardKeyboardHighlightStaysAbovePager() async throws {
    let board = BottomChromeBandBoard.bandRankings
    let pageRows = 25
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongBandBoardsTransport())
    let session = FestivalSession(factory: { client })
    let recorder = BoardKeyPushRecorder()
    let size = CGSize(width: 402, height: 700)
    let screen = try await board.screen(session)
    let host = nativeHostedView(
        NavigationStack {
            screen
                .modifier(MacKeyboardNavigation(selection: nil, select: nil, push: { recorder.pushed.append($0) }, isTop: true))
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size, forceGlassFallback: false
    )
    let window = NSWindow(
        contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: [board.loadedText], timeout: .seconds(60))
    let scroll = try #require(boardScrollView(in: host))
    let scrollFrame = scroll.convert(scroll.bounds, to: host)
    let chromeTop = scrollFrame.maxY - scroll.contentInsets.bottom
    let visibleTop = scrollFrame.minY + scroll.contentInsets.top

    // The last row wholly above the fade before any key: ↓ must carry the highlight past it.
    let initial = boardAccessibilityNodes(in: host)
    let lastClear = try #require(initial.compactMap { node -> Int? in
        guard let rank = board.rank(of: node.identifier), let frame = node.frame,
              frame.maxY <= chromeTop - ScrollEdgeFade.distance else { return nil }
        return rank
    }.max())
    #expect(lastClear < pageRows, "the page runs past the fold")

    func highlighted() -> (rank: Int, node: BoardAccessibilityNode)? {
        boardAccessibilityNodes(in: host).compactMap { node in
            board.rank(of: node.identifier).map { ($0, node) }
        }.first { $0.node.selected }
    }

    for expected in 1...min(lastClear + 4, pageRows) {
        sendBoardKey("down", to: window)
        _ = try await nativeHostedSettle(host)
        let row = try #require(highlighted(), "↓ highlights a row (\(expected))")
        #expect(row.rank == expected, "↓ moves the highlight one row: \(row.rank) vs \(expected)")
        #expect(row.node.isButton && row.node.enabled, "the highlighted row is an enabled button")
        let frame = try #require(row.node.frame)
        #expect(frame.maxY <= chromeTop + 0.5, "highlighted row \(row.rank) is not under the pager: \(frame) vs \(chromeTop)")
        #expect(frame.minY >= visibleTop - 0.5, "highlighted row \(row.rank) is on screen: \(frame)")
    }
    #expect(scroll.contentView.bounds.minY + scroll.contentInsets.top > 1, "↓ past the fold scrolled the board")

    // End: the page's last row, resting wholly above the pager; Return opens it.
    sendBoardKey("end", to: window)
    _ = try await nativeHostedSettle(host)
    let last = try #require(highlighted(), "End highlights a row")
    #expect(last.rank == pageRows, "End reaches the last row: \(last.rank)")
    let lastFrame = try #require(last.node.frame)
    #expect(lastFrame.maxY <= chromeTop + 0.5, "the last row is not under the pager: \(lastFrame) vs \(chromeTop)")
    try expectFirstPagePager(boardAccessibilityNodes(in: host), board: board, chromeTop: chromeTop)
    sendBoardKey("return", to: window)
    _ = try await nativeHostedSettle(host) { !recorder.pushed.isEmpty }
    #expect(recorder.pushed.count == 1, "Return opens the highlighted row: \(recorder.pushed)")
    withExtendedLifetime(window) {}
}

/// The other paginated boards whose pinned chrome goes through `boardBottomChrome`.
enum BoardChromeOrderBoard: String, CaseIterable, CustomTestStringConvertible {
    case solo, fullRankings, playerBands

    var testDescription: String { rawValue }

    /// Identifier prefix of the board's rows.
    var rowPrefix: String {
        switch self {
        case .solo: "fst.song-leaderboard.row."
        case .fullRankings: "fst.rankings.row."
        case .playerBands: "fst.player-bands.row."
        }
    }

    /// Identifier prefix of the board's footer and pager.
    var chromePrefix: String {
        switch self {
        case .solo: "fst.song-leaderboard"
        case .fullRankings: "fst.full-rankings"
        case .playerBands: "fst.player-bands"
        }
    }

    /// Whether `identifier` names part of the pinned chrome (footer or pager).
    func isChrome(_ identifier: String) -> Bool {
        identifier.hasPrefix("\(chromePrefix).page-") || identifier.hasPrefix("\(chromePrefix).spotlight")
    }

    /// The board with its fixtures, a selected player (and so a footer) where it has one.
    @MainActor
    func screen() async throws -> AnyView {
        switch self {
        case .solo:
            let session = try await spotlightSelectedSession()
            return AnyView(SoloLeaderboardScreen(
                song: try spotlightFixtureSong(), instrument: .lead, session: session,
                initialPage: 1, path: .constant([]),
                initialState: .loaded(try spotlightFixtureLeaderboard(spotlightRank: 3))
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
        case .playerBands:
            let fixture = try await bandsFixtureSession()
            return AnyView(PlayerBandsScreen(
                session: fixture.session, accountId: "fixture-player-1", displayName: "Fixture Player 1"
            ))
        }
    }
}

/// Issue #473: on every paginated board the pinned footer and pager read after the
/// rows, as drawn. Hosted at a navigation destination's root (as the app shows them),
/// macOS listed a bottom safe-area inset before the scroll view, so VoiceOver reached
/// the band song leaderboard's pager before any band (`boardBottomChrome`, scroll-edge R10).
@MainActor
@Test(.serialized, arguments: BoardChromeOrderBoard.allCases)
func boardBottomChromeReadsAfterRows(board: BoardChromeOrderBoard) async throws {
    let size = CGSize(width: 402, height: 900)
    let screen = try await board.screen()
    let host = nativeHostedView(
        NavigationStack { screen }
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        let nodes = boardAccessibilityNodes(in: host)
        return nodes.contains { $0.identifier.hasPrefix(board.rowPrefix) }
            && nodes.contains { $0.identifier == "\(board.chromePrefix).page-first" }
    }
    let nodes = boardAccessibilityNodes(in: host)
    let lastRow = try #require(nodes.lastIndex { $0.identifier.hasPrefix(board.rowPrefix) })
    let firstChrome = try #require(nodes.firstIndex { board.isChrome($0.identifier) })
    #expect(
        lastRow < firstChrome,
        "rows read before the footer and pager: \(nodes.map(\.identifier).filter { $0.hasPrefix(board.rowPrefix) || board.isChrome($0) })"
    )
    let chrome = nodes.filter { board.isChrome($0.identifier) }.map(\.identifier)
    #expect(chrome.contains("\(board.chromePrefix).page-last"), "the pager is reachable: \(chrome)")
}
#endif
