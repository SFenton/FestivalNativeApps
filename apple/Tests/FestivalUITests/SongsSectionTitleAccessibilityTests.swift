#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// One grouped Songs sort and the section titles it must announce, in list order.
struct SongsTitleCase: CustomTestStringConvertible, Sendable {
    let mode: SongSortMode
    /// Per-song wire overrides (`songId` → field → value) on the shared two-song fixture.
    let overrides: [String: [String: String]]
    /// Expected titles in sort order: accessibility ID, spoken label, then the songs under it.
    let sections: [(id: String, label: String, songs: [String])]

    var testDescription: String { mode.rawValue }
}

/// The four Songs groupings #91 touched: three Quick Links sorts and the A–Z titles
/// they now match. Score/Percentile/Stars use the same `bucketed` titles as Duration.
let songsTitleCases: [SongsTitleCase] = [
    SongsTitleCase(
        mode: .shop, overrides: [:],
        sections: [
            ("fst.songs.shop-section.leaving-tomorrow", "Leaving Tomorrow", ["fixture-orbit"]),
            ("fst.songs.shop-section.in-shop", "In Shop", ["fixture-pulse"]),
        ]
    ),
    SongsTitleCase(
        mode: .duration,
        overrides: ["fixture-pulse": ["durationSeconds": "45"], "fixture-orbit": ["durationSeconds": "200"]],
        sections: [
            ("fst.songs.duration-section.under1", "Under 1 Minute", ["fixture-pulse"]),
            ("fst.songs.duration-section.3to4", "3–4 Minutes", ["fixture-orbit"]),
        ]
    ),
    SongsTitleCase(
        mode: .year,
        overrides: ["fixture-orbit": ["year": "1995"]],
        sections: [
            ("fst.songs.year-section.1990", "1990s", ["fixture-orbit"]),
            ("fst.songs.year-section.2020", "2020s", ["fixture-pulse"]),
        ]
    ),
    SongsTitleCase(
        mode: .title,
        overrides: ["fixture-orbit": ["title": "Orbit Fixture"]],
        sections: [
            ("fst.songs.section.0", "F", ["fixture-pulse"]),
            ("fst.songs.section.1", "O", ["fixture-orbit"]),
        ]
    ),
]

/// Apply a case's per-song overrides to the committed Songs fixture bytes.
///
/// - Parameters:
///   - catalogue: Original `songs-demo.json` envelope.
///   - overrides: `songId` → wire field → value (integers stay integers).
/// - Returns: The re-encoded envelope.
/// - Throws: A malformed fixture or a song the fixture lacks.
private func songsTitleCatalogue(
    _ catalogue: Data, overrides: [String: [String: String]]
) throws -> Data {
    var envelope = try #require(try JSONSerialization.jsonObject(with: catalogue) as? [String: Any])
    var songs = try #require(envelope["songs"] as? [[String: Any]])
    for (songId, fields) in overrides {
        let index = try #require(songs.firstIndex { $0["songId"] as? String == songId })
        for (key, value) in fields { songs[index][key] = Int(value) ?? value }
    }
    envelope["songs"] = songs
    return try JSONSerialization.data(withJSONObject: envelope)
}

/// Host the real Songs list for one sort over the in-memory fixture transport.
///
/// - Parameters:
///   - testCase: Sort and catalogue overrides.
///   - storage: Private defaults suite for the sort and accessibility settings.
/// - Returns: Settled host and its never-shown window (retain both while reading).
/// - Throws: A failed fixture load or unrealized section titles.
@MainActor
private func hostSongsTitles(
    _ testCase: SongsTitleCase, storage: UserDefaults
) async throws -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    storage.set(true, forKey: "fst.accessibility.lessTransparency")
    storage.set(true, forKey: "fst.accessibility.moreContrast")
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    storage.set(testCase.mode.rawValue, forKey: "fst.songs.sortMode")
    storage.set(true, forKey: "fst.songs.sortAscending")
    storage.set(false, forKey: "fst.settings.hideShop")
    let fixtures = try shopFixtureBytes()
    let transport = HostedShopTransport(
        scenario: .populated, offers: fixtures.offers,
        catalogue: try songsTitleCatalogue(fixtures.catalogue, overrides: testCase.overrides)
    )
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    _ = try await session.shop()
    let payload = try await session.catalog()
    let size = CGSize(width: 390, height: 844)
    let host = nativeHostedView(
        NavigationStack {
            SongsScreen(
                session: session, initialState: .loaded(payload),
                searchText: .constant(""), settledSearch: .constant(""),
                selectedInstrument: .constant(nil), isVisible: false, openShop: {}
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
        .tint(BrandTokens.accentBlue),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    let wanted = testCase.sections.map(\.id) + testCase.sections.flatMap(\.songs).map { "fst.songs.row.\($0)" }
    try await nativeHostedSettle(host) {
        let identifiers = Set(nativeHostedAccessibility(host).identifiers)
        return wanted.allSatisfy(identifiers.contains)
    }
    return (host, window)
}

// MARK: - Tests

/// Songs section titles for the grouped sorts (#91, tests #441): after #91 moved their
/// row traits outside the Quick Links anchor, each title is still one named heading
/// that reads before its songs, keeps its full height and stays legible with no backing.
///
/// macOS does not scale fonts with Dynamic Type; the iPhone AX5 check is
/// `SongsJourneyTests.testSongsShopSortSectionTitlesAreAccessibleAtAX5`.
@Suite("Songs section title accessibility (#91)")
@MainActor
struct SongsSectionTitleAccessibilityTests {
    /// Every title is an `AXHeading` named exactly as shown (section-headers R1), not a
    /// button and not hidden (R6), and VoiceOver reads titles and songs in list order:
    /// a title, then its songs, then the next title (HIG VoiceOver: "Use accurate
    /// section headings").
    @Test(arguments: songsTitleCases)
    func titlesAreNamedHeadingsReadBeforeTheirSongs(_ testCase: SongsTitleCase) async throws {
        let suite = "fst-songs-titles-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let (host, window) = try await hostSongsTitles(testCase, storage: storage)
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "songs-titles-\(testCase.mode.rawValue)")
        let elements = nodes.filter(\.isElement)
        var previous = -1
        for section in testCase.sections {
            let matches = elements.enumerated().filter { $0.element.identifier == section.id }
            #expect(matches.count == 1, "\(section.id) is not one element: \(matches.map(\.element))")
            let (index, title) = try #require(matches.first)
            #expect(title.role == "AXHeading", "\(section.id) role \(title.role)")
            #expect(title.spokenName == section.label)
            #expect(index > previous, "\(section.label) reads before the songs above it")
            previous = index
            for songId in section.songs {
                let row = try #require(
                    elements.firstIndex { $0.identifier == "fst.songs.row.\(songId)" },
                    "\(songId) row is not an accessibility element"
                )
                #expect(row > index, "\(songId) reads before its title \(section.label)")
                previous = max(previous, row)
            }
        }
        // The floating section bar's copies stay out of the tree (R6): one heading per title.
        let headings = elements.filter { $0.role == "AXHeading" }.map(\.spokenName)
        #expect(headings == testCase.sections.map(\.label), "headings \(headings)")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
        withExtendedLifetime(host) {}
    }

    /// Each title is at least one text line tall (not clipped), sits directly above its
    /// own songs with the A–Z titles' spacing (#91's lost row insets pushed it toward the
    /// previous section), and its rendered text keeps 4.5:1 contrast against the page
    /// behind it, now that #91 removed the opaque row backing.
    @Test(arguments: songsTitleCases)
    func titlesKeepTheirTextHeightAndContrast(_ testCase: SongsTitleCase) async throws {
        let suite = "fst-songs-titles-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let (host, window) = try await hostSongsTitles(testCase, storage: storage)
        defer { window.orderOut(nil) }
        let font = NSFont.boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize)
        let lineHeight = ceil(font.ascender - font.descender)
        for section in testCase.sections {
            let frame = try #require(nativeHostedAccessibilityFrame(section.id, in: host))
            #expect(frame.height >= lineHeight, "\(section.label) \(frame) clips its \(lineHeight)pt line")
            #expect(frame.minX >= 0 && frame.maxX <= host.bounds.width + 0.5)
            // The title sits right above its own songs, as A–Z titles do: with the List's
            // default row inset (#91) the gap doubled and the title drifted toward the
            // previous section's songs.
            let firstSong = try #require(section.songs.first)
            let row = try #require(nativeHostedAccessibilityFrame("fst.songs.row.\(firstSong)", in: host))
            let gap = row.minY - frame.maxY
            #expect(
                gap >= 0 && gap <= SongsScrollChrome.inlineTitleBottomPadding + 3,
                "\(section.label) sits \(gap)pt above its first song"
            )
            let crop = try nativeHostedImage(host, in: CGRect(
                x: frame.minX, y: frame.minY, width: min(frame.width, 200), height: frame.height
            ))
            let contrast = songsTitleContrast(crop)
            #expect(contrast.inkPixels > 20, "\(section.label) paints no text")
            #expect(contrast.ratio >= 4.5, "\(section.label) contrast \(contrast)")
        }
        withExtendedLifetime(host) {}
    }
}

/// WCAG contrast between a crop's median surface and its brightest glyph pixels.
///
/// - Parameter image: A title's rendered region.
/// - Returns: The ratio and how many pixels are clearly brighter than the surface.
@MainActor
private func songsTitleContrast(_ image: CGImage) -> (ratio: Double, inkPixels: Int) {
    let bitmap = NSBitmapImageRep(cgImage: image)
    var luminances: [Double] = []
    for y in 0..<image.height {
        for x in 0..<image.width {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            luminances.append(
                0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
                    + 0.0722 * linear(color.blueComponent)
            )
        }
    }
    luminances.sort()
    guard !luminances.isEmpty else { return (0, 0) }
    let background = luminances[luminances.count / 2]
    let text = luminances[luminances.count * 99 / 100]
    return ((text + 0.05) / (background + 0.05), luminances.filter { $0 > background * 3 + 0.01 }.count)
}
#endif
