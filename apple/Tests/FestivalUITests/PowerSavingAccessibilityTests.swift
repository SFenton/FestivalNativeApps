#if os(macOS)
import AppKit
import Foundation
import QuartzCore
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Power-saving changes, accessibility (issue #28, backfilled by #403)

/// Issue #28 cut idle power on iPhone: the album-art backdrop became a Core Animation
/// layer tree (``CarouselSlotView``) that holds still when its page may not animate
/// (Reduce Motion, a covering sheet), first-run demo pulses loop only on the visible slide,
/// and ``ArtworkTile`` draws covers this session already decoded in a row's first frame
/// (Suggestions scrolling). The policies are unit tested (`artworkPolicyHonorsSystemAndAppOverrides`,
/// `firstRunPulseRunsOnlyOnTheVisibleSlide`); these hosted checks pin what VoiceOver gets
/// from the changed views on every Apple platform (the same SwiftUI and slot view run on
/// iPhone, iPad, iPhone Duo and Mac):
///
/// - a Suggestions row whose cover came from the cache reads the song, in visual order,
///   as one element of at least 44 pt that grows and stays on the page at AX5;
/// - the album-art tile is decorative in every state, even inside a row that combines its
///   children (Global Search, Band detail), where it used to read "Cached album artwork";
/// - the backdrop slot is never an accessibility element and runs no animation when motion
///   is off;
/// - a first-run pulse adds no element, running or still.
///
/// HIG VoiceOver: "Exclude purely decorative images that convey no useful or actionable
/// information". HIG Accessibility: "When Reduce Motion is on, reduce automatic and
/// repetitive animation, including zooming, scaling, and peripheral motion"; iOS/iPadOS
/// default control size 44×44 pt.
@MainActor
@Suite(.serialized)
struct PowerSavingAccessibilityTests {
    // MARK: - Fixture

    /// Loopback fixture cover (`Fixtures/pulse.png`), served by ``ArtworkFixtureTransport``.
    static let artPath = "/__fixture__/art/pulse.png"
    static let title = "Fixture Pulse and the Unusually Long Suggestion Title"
    static let artist = "Fixture Artist"

    /// Every API read fails: these tests only exercise the decoded-artwork cache.
    private actor NoServiceTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> HTTPResult {
            throw FestivalAPIError.invalidResource
        }
    }

    /// A session whose decoded-art cache already holds the fixture cover at a 44 pt tile's
    /// size, so a new tile takes #28's synchronous first-frame path.
    ///
    /// - Returns: The session.
    /// - Throws: A missing fixture or a failed decode.
    static func cachedArtSession() async throws -> FestivalSession {
        let png = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
        let client = try FestivalAPI(
            baseURL: URL(string: "http://127.0.0.1:8765")!, transport: NoServiceTransport()
        )
        let session = FestivalSession(
            factory: { client },
            artwork: ArtworkCache(transport: ArtworkFixtureTransport(data: try Data(contentsOf: png)))
        )
        let edge = ArtworkTile.decodedEdge(for: 44)
        _ = try await session.preparedArtwork(raw: artPath, maxPixels: edge)
        #expect(session.cachedArtwork(raw: artPath, maxPixels: edge) != nil, "cover decoded")
        return session
    }

    /// A catalogue song with the fixture cover.
    static func song() throws -> Song {
        try JSONDecoder().decode(Song.self, from: Data("""
        {"songId":"fixture-pulse","title":"\(title)","artist":"\(artist)","album":null,"year":2024,
         "durationSeconds":null,"albumArt":"\(artPath)","difficulty":null,
         "pathArtifactGenerationId":null,"sig":null,"maxScores":null}
        """.utf8))
    }

    /// Text that names the artwork tile in any of its states.
    static let artworkWords = ["artwork", "Artwork", "photo", "music.note", "Loading"]

    /// Nodes VoiceOver could land on that mention the artwork tile.
    static func artworkLeaks(_ nodes: [MacAXNode]) -> [String] {
        nodes.filter { node in
            node.isElement && (node.role == "AXImage" || node.role == "AXBusyIndicator"
                || artworkWords.contains { word in
                    [node.label, node.title, node.value, node.help].contains { $0.contains(word) }
                })
        }.map(\.description)
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    // MARK: - Suggestions row

    /// A Suggestions card whose row drew its cover from the cache, at `size`.
    static func suggestionCard(
        session: FestivalSession, size: DynamicTypeSize
    ) throws -> NSHostingView<some View> {
        let item = SuggestionSongItem(song: try song(), instrument: .lead, stars: 4)
        let category = SuggestionCategory(
            key: "star_gains_lead", title: "Star Gains", description: "One more star.",
            type: .starProgress, instrument: .lead, songs: [item]
        )
        return nativeHostedView(
            SuggestionCategoryCardView(category: category, session: session)
                .frame(width: 320)
                .environment(\.dynamicTypeSize, size)
                .environment(\.marqueeAnimationEnabled, false)
                .preferredColorScheme(.dark),
            size: CGSize(width: 320, height: 640)
        )
    }

    /// The Suggestions row reads the song, never its cached cover: one element whose name
    /// runs title → "artist · year" → metadata, at least 44 pt tall and on the page; at AX5
    /// the row grows (the title wraps and the metadata stacks) and stays on the page.
    @Test func suggestionRowWithCachedCoverReadsTheSongInOrder() async throws {
        let session = try await Self.cachedArtSession()
        var heights: [DynamicTypeSize: CGFloat] = [:]
        for size in [DynamicTypeSize.large, .accessibility5] {
            let host = try Self.suggestionCard(session: session, size: size)
            let window = nativeHostedWindow(host, size: CGSize(width: 320, height: 640))
            defer { window.orderOut(nil) }
            // The card's own identifier reaches its children in hosting, so find the row by
            // role and name: the one button that reads the song.
            func rowElement() -> NSObject? {
                nativeHostedAccessibilityElement(in: host) {
                    nativeHostedAccessibilityString($0, "accessibilityRole") == "AXButton"
                        && nativeHostedAccessibilityString($0, "accessibilityLabel").contains(Self.title)
                }
            }
            try await nativeHostedSettle(host) { rowElement() != nil }
            let nodes = macAccessibilityTree(host, navigationOrder: true)
            #expect(Self.artworkLeaks(nodes).isEmpty, "\(size): \(Self.dump(nodes))")
            let rows = nodes.filter { $0.isElement && $0.role == "AXButton" }
            #expect(rows.count == 1, "\(size): one row element: \(Self.dump(nodes))")
            let row = try #require(rows.first)
            #expect(row.label.contains(Self.title), "\(size): \(row)")
            let name = [row.label, row.title, row.value].joined(separator: " ")
            let title = try #require(name.range(of: Self.title), "\(size): title in '\(name)'")
            let artist = try #require(name.range(of: "\(Self.artist) \u{00B7} 2024"), "\(size): subtitle in '\(name)'")
            let stars = try #require(name.range(of: "4 stars"), "\(size): stars in '\(name)'")
            let instrument = try #require(name.range(of: "Lead"), "\(size): instrument in '\(name)'")
            #expect(title.upperBound <= artist.lowerBound && artist.upperBound <= stars.lowerBound
                    && stars.upperBound <= instrument.lowerBound, "\(size): reads in visual order: '\(name)'")
            // No row text is announced twice (a static marquee draws one Text since #28).
            #expect(nodes.filter { $0.isElement && $0.spokenName.contains(Self.title) }.count == 1,
                    "\(size): \(Self.dump(nodes))")

            host.layoutSubtreeIfNeeded()
            let element = try #require(rowElement())
            let frame = try #require(nativeHostedAccessibilityFrame(of: element, in: host), "\(size): row frame")
            #expect(frame.height >= 43, "\(size): 44 pt target, got \(frame.height)")
            #expect(host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(size): row on the page: \(frame)")
            heights[size] = frame.height
        }
        let large = try #require(heights[.large])
        let ax5 = try #require(heights[.accessibility5])
        #expect(ax5 > large * 1.35, "AX5 row grows: \(ax5) vs \(large)")
    }

    // MARK: - Artwork tile

    /// The album-art tile is decorative whichever path drew it: the cached first frame
    /// (#28), no artwork or a failed load. Inside a row that combines its children (Global
    /// Search, Band detail) the row reads only its text.
    @Test func artworkTileIsDecorativeInEveryState() async throws {
        let session = try await Self.cachedArtSession()
        let states: [(name: String, raw: String?)] = [
            ("cached", Self.artPath), ("no artwork", nil), ("invalid path", "../outside.png"),
        ]
        for state in states {
            let host = nativeHostedView(
                HStack(spacing: 12) {
                    ArtworkTile(raw: state.raw, session: session, size: 44)
                    Text(Self.title).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("fst.test.combined-row")
                .frame(width: 320, height: 64),
                size: CGSize(width: 320, height: 64)
            )
            let window = nativeHostedWindow(host, size: CGSize(width: 320, height: 64))
            defer { window.orderOut(nil) }
            try await nativeHostedSettle(host) {
                nativeHostedAccessibilityElement("fst.test.combined-row", in: host) != nil
            }
            let nodes = macAccessibilityTree(host)
            #expect(Self.artworkLeaks(nodes).isEmpty, "\(state.name): \(Self.dump(nodes))")
            let row = try #require(nodes.first { $0.identifier == "fst.test.combined-row" })
            #expect(row.spokenName == Self.title, "\(state.name): row reads only its text: \(row)")
        }
    }

    // MARK: - Backdrop slot

    /// The Core Animation backdrop slot (#28) is never an accessibility element or click
    /// target, and with motion off (Reduce Motion, a covering sheet, an inactive page) it
    /// holds a still frame with no animation on its layer tree.
    @Test func carouselSlotIsDecorativeAndStillWithoutMotion() throws {
        let png = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
        let source = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let slot = CarouselSlotView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 640),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.contentView = slot
        window.orderOut(nil)
        defer { window.orderOut(nil) }

        func animationKeys() -> [String] {
            var keys: [String] = []
            func walk(_ layer: CALayer) {
                keys += layer.animationKeys() ?? []
                layer.sublayers?.forEach(walk)
            }
            slot.layer.map(walk)
            return keys
        }
        let now = Date()
        let layer = ArtworkBackdropState.Layer(
            id: 0, visible: true, moving: true, motion: ArtworkMotionPreset.all[2],
            fadeStart: now, motionStart: now
        )
        slot.apply(image: image, layer: layer, isActive: true, lightness: 0.6, animate: true)
        #expect(!animationKeys().isEmpty, "motion allowed: the slot zooms/pans and fades")

        slot.apply(image: image, layer: layer, isActive: true, lightness: 0.6, animate: false)
        #expect(animationKeys().isEmpty, "motion off: no animation, got \(animationKeys())")

        #expect(!slot.isAccessibilityElement())
        #expect((slot.accessibilityChildren() ?? []).isEmpty)
        #expect(slot.hitTest(NSPoint(x: 160, y: 320)) == nil)
    }

    // MARK: - First-run pulse

    /// A first-run pulse adds nothing to the accessibility tree, whether it loops (the
    /// visible slide) or holds still (another slide, #28): the card keeps its one name.
    @Test func firstRunPulseAddsNoAccessibilityElement() async throws {
        for active in [true, false] {
            let host = nativeHostedView(
                Text("Demo card")
                    .padding(16)
                    .firstRunPulse(.purple)
                    .environment(\.firstRunSlideActive, active)
                    .frame(width: 240, height: 120),
                size: CGSize(width: 240, height: 120)
            )
            let window = nativeHostedWindow(host, size: CGSize(width: 240, height: 120))
            defer { window.orderOut(nil) }
            try await nativeHostedSettle(host, untilText: ["Demo card"])
            let elements = macAccessibilityTree(host).filter {
                $0.isElement && !ReloadGateAccessibilityTests.containerRoles.contains($0.role)
            }
            #expect(elements.map(\.spokenName) == ["Demo card"],
                    "slide active \(active): \(Self.dump(elements))")
        }
    }
}
#endif
