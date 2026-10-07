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
#endif
