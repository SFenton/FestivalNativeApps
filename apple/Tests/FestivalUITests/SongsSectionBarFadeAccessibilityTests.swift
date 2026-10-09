#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// Keyless fixture transport for an A–H Songs catalogue long enough to scroll several
/// sections under the floating section bar (issue #391). Rejects the privileged key,
/// selected-profile headers, writes and any other route.
private actor SectionBarCatalogueTransport: HTTPTransport {
    static let letters = Array("ABCDEFGH").map(String.init)
    static let perLetter = 6
    private let generation = 31

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
        guard url.path == "/api/songs",
              request.value(forHTTPHeaderField: "X-FST-Publication-Id") == String(generation) else {
            throw FestivalAPIError.httpStatus(404)
        }
        let songs = Self.letters.flatMap { letter in
            (1...Self.perLetter).map { index in
                """
                {"songId":"bar-\(letter.lowercased())\(index)","title":"\(letter) Song \(index)",
                 "artist":"The Fixtures","album":null,"year":2024,"durationSeconds":180,
                 "albumArt":null,"difficulty":null,"pathArtifactGenerationId":null}
                """
            }
        }
        return HTTPResult(status: 200, data: Data("""
        {"count":\(songs.count),"currentSeason":40,"songs":[\(songs.joined(separator: ","))]}
        """.utf8), headers: ["X-FST-Publication-Id": String(generation)])
    }
}

// MARK: - Hosting

/// The Songs List's own scroll view: the deepest scroll view whose document is a table.
@MainActor
private func songsListScrollView(in view: NSView) -> NSScrollView? {
    for subview in view.subviews {
        if let found = songsListScrollView(in: subview) { return found }
    }
    if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
    return nil
}

/// A Songs screen hosted in a window with the list scrolled, for one accessibility mode.
@MainActor
private struct HostedSongs {
    let host: NSView
    let window: NSWindow
    let suite: String
    let size: CGSize
    /// Waits for the hosted view to settle and renders it (``nativeHostedSettle(_:timeout:animationGrace:)``).
    let settle: @MainActor () async throws -> CGImage

    /// Host the fixture catalogue's Songs screen with the floating section bar.
    ///
    /// - Parameter mode: The transparency/contrast setting to host under.
    static func make(mode: BottomChromeFadeMode) async throws -> HostedSongs {
        let client = try FestivalAPI(
            baseURL: URL(string: "http://localhost")!, transport: SectionBarCatalogueTransport()
        )
        let session = FestivalSession(factory: { client })
        let payload = try await session.catalog()
        let size = CGSize(width: 402, height: 700)
        let (defaults, suite) = mode.storage()
        let host = nativeHostedView(
            mode.system(
                NavigationStack {
                    SongsScreen(session: session, initialState: .loaded(payload), isVisible: false)
                }
                .frame(width: size.width, height: size.height)
                .defaultAppStorage(defaults)
                .preferredColorScheme(.dark)
            ),
            size: size,
            // The real transparency setting: the fallback forces Reduce Transparency.
            forceGlassFallback: false
        )
        let window = nativeHostedWindow(host, size: size)
        _ = try await nativeHostedSettle(host, untilText: ["A Song 1"])
        return HostedSongs(
            host: host, window: window, suite: suite, size: size,
            settle: { try await nativeHostedSettle(host) }
        )
    }

    /// Scroll the list so `offset` points of content lie above its top and settle.
    ///
    /// - Returns: The settled rendering.
    func scroll(to offset: CGFloat) async throws -> CGImage {
        let scroll = try #require(songsListScrollView(in: host))
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: offset - scroll.contentInsets.top))
        scroll.reflectScrolledClipView(clip)
        return try await settle()
    }

    /// The pinned title's bottom edge, where the row fade starts.
    func fadeEdge() throws -> CGFloat {
        let bar = try #require(nativeHostedAccessibilityFrame("fst.songs.section-bar", in: host))
        return bar.maxY + SongsScrollChrome.barTitleBottomPadding
    }

    /// Close the window and drop this mode's defaults suite.
    func close() {
        window.orderOut(nil)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }
}

/// Six 68 pt rows per letter: 527 pt sits inside B with B pinned, 420 pt is mid-push
/// (B's in-list title is pushing the pinned A out).
private let pinnedOffset: CGFloat = 527
private let pushOffset: CGFloat = 420

// MARK: - Tests

/// Issue #391 (#10's fade): the floating section title stays one VoiceOver heading that
/// names the current section and comes before the list, while it is pinned and while the
/// next title pushes it out. The pushed-out and incoming copies the bar draws stay hidden
/// (section-headers R6), so heading navigation meets each section's title once in the
/// list plus the bar, never a moving copy. Every element stays named.
@MainActor
@Test(arguments: [(pinnedOffset, "B"), (pushOffset, "A")])
func songsSectionBarIsOneHeadingBeforeTheList(offset: CGFloat, current: String) async throws {
    let hosted = try await HostedSongs.make(mode: .standard)
    defer { hosted.close() }
    _ = try await hosted.scroll(to: offset)

    let tree = macAccessibilityTree(hosted.host)
    let elements = tree.filter(\.isElement)
    let headings = elements.filter { $0.role == "AXHeading" }
    let bars = headings.filter { $0.identifier == "fst.songs.section-bar" }
    #expect(bars.count == 1, "\(headings)")
    #expect(bars.first?.label == current)
    #expect(bars.first?.spokenName == current)
    let others = headings.filter { $0.identifier != "fst.songs.section-bar" }
    #expect(others.allSatisfy { $0.identifier.hasPrefix("fst.songs.section.") },
            "A moving bar copy is exposed: \(others)")
    #expect(Set(others.map(\.identifier)).count == others.count, "\(others)")

    let barIndex = try #require(tree.firstIndex { $0.identifier == "fst.songs.section-bar" })
    let listIndex = try #require(tree.firstIndex { $0.identifier == "fst.songs.list" })
    #expect(barIndex < listIndex, "The current section title must be read before its rows")
    #expect(macAccessibilityFindings(tree).isEmpty, "\(macAccessibilityFindings(tree))")

    let bar = try #require(nativeHostedAccessibilityFrame("fst.songs.section-bar", in: hosted.host))
    #expect(bar.width > 0 && bar.height > 0)
}

/// Issue #391: rows crossing the fade under the pinned title stay named, actionable
/// buttons with a full-height target: the mask is visual only and hides no row.
@MainActor
@Test func songsRowUnderTheSectionBarFadeStaysANamedButton() async throws {
    let hosted = try await HostedSongs.make(mode: .standard)
    defer { hosted.close() }
    _ = try await hosted.scroll(to: pinnedOffset)
    let band = try CGRect(
        x: 0, y: hosted.fadeEdge(), width: hosted.size.width, height: PinnedHeaderEdgeFade.height
    )

    let rows = macAccessibilityTree(hosted.host).filter {
        $0.isElement && $0.identifier.hasPrefix("fst.songs.row.")
    }
    let faded = rows.filter {
        nativeHostedAccessibilityFrame($0.identifier, in: hosted.host)?.intersects(band) == true
    }
    #expect(!faded.isEmpty, "No row crosses the fade band \(band)")
    for row in faded {
        #expect(row.role == "AXButton", "\(row)")
        #expect(row.label.hasPrefix("B Song"), "\(row)")
        let frame = try #require(nativeHostedAccessibilityFrame(row.identifier, in: hosted.host))
        #expect(frame.height >= 44, "\(row.identifier) target \(frame)")
    }
}

/// Issue #391 (scroll-edge R7): with Reduce Transparency, Increase Contrast or the app's
/// Less Transparency / More Contrast, rows meet the pinned title at a hard edge instead of
/// fading, and the switch changes nothing VoiceOver sees: the same elements, names and
/// order, and the bar in the same place.
@MainActor
@Test(arguments: BottomChromeFadeMode.allCases.filter(\.hardEdge))
func songsSectionBarHardEdgeKeepsTheAccessibilityTree(mode: BottomChromeFadeMode) async throws {
    func signature(_ hosted: HostedSongs) -> [String] {
        macAccessibilityTree(hosted.host).filter(\.isElement).map {
            "\($0.role)|\($0.label)|\($0.identifier)"
        }
    }
    func justBelow(_ edge: CGFloat) -> CGRect { CGRect(x: 0, y: edge + 1, width: 340, height: 9) }

    let standard = try await HostedSongs.make(mode: .standard)
    let fadedImage = try await standard.scroll(to: pinnedOffset)
    let fadedEdge = try standard.fadeEdge()
    let fadedTree = signature(standard)
    standard.close()

    let hard = try await HostedSongs.make(mode: mode)
    defer { hard.close() }
    let hardImage = try await hard.scroll(to: pinnedOffset)
    let hardEdge = try hard.fadeEdge()

    #expect(hardEdge == fadedEdge)
    #expect(signature(hard) == fadedTree)
    // Row text just under the title: dimmed by the fade, at full strength at a hard edge.
    let faded = nativeHostedBrightSamples(
        in: justBelow(fadedEdge), of: fadedImage, hostSize: standard.size, threshold: 100
    )
    let solid = nativeHostedBrightSamples(
        in: justBelow(hardEdge), of: hardImage, hostSize: hard.size, threshold: 100
    )
    #expect(faded == 0, "Rows are not faded under the title (\(faded) bright samples)")
    #expect(solid > 0, "\(mode) still fades rows under the title")
}
#endif
