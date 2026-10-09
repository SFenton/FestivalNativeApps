#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - First-run song demo accessibility (issue #26, backfilled by #401)

/// Issue #26 moved every song-using first-run demo from invented titles to real catalogue
/// songs (``FirstRunCatalogueSongs``), with redacted placeholder rows while the catalogue
/// loads or is unavailable. The demos are decorative pictures of the app: the slide's title
/// and description are its one accessible element. These hosted checks pin that, in both
/// demo states, on every Apple platform (the carousel is the same SwiftUI on iPhone, iPad,
/// iPhone Duo and Mac): no placeholder or song text reaches VoiceOver, the slide reads before
/// the page dots and actions, the actions keep full-size targets, and at the largest
/// accessibility text size the slide text and actions stay reachable. HIG VoiceOver:
/// "Exclude purely decorative images that convey no useful or actionable information";
/// HIG Accessibility: iOS/iPadOS default control size 44×44 pt.
@MainActor
@Suite(.serialized)
struct FirstRunDemoSongsAccessibilityTests {
    // MARK: - Fixture

    /// Every slide whose demo shows songs through ``FirstRunCatalogueSongs`` (issue #26).
    static let songDemoSlides: [(page: FirstRunPageKey, id: String)] = [
        (.songs, "songs-song-list"), (.songs, "songs-icons"), (.songs, "songs-metadata"),
        (.songs, "songs-shop-highlight"), (.songs, "songs-new-in-shop"), (.songs, "songs-leaving-tomorrow"),
        (.songInfo, "songinfo-shop-button"), (.songInfo, "songinfo-new-in-shop"),
        (.songInfo, "songinfo-leaving-tomorrow"),
        (.statistics, "statistics-top-songs"),
        (.suggestions, "suggestions-category-card"), (.suggestions, "suggestions-infinite-scroll"),
        (.rivals, "rivals-detail"),
        (.shop, "shop-overview"), (.shop, "shop-highlighting"), (.shop, "shop-new-items"),
        (.shop, "shop-leaving-tomorrow"),
    ]

    /// Song titles in the checked-in catalogue fixture (`contracts/fixtures/songs-demo.json`).
    static let fixtureTitles = ["Fixture Pulse", "Fixture Orbit"]

    /// Text no accessibility element may carry: placeholder stand-ins and catalogue songs.
    static let forbiddenText = ["Placeholder", "Synthetic Quartet"] + fixtureTitles

    /// A session whose catalogue is the checked-in fixture, already loaded.
    ///
    /// - Returns: A session over the fixture transport (no live service).
    /// - Throws: Missing fixture or a failed fixture read.
    static func liveSession() async throws -> FestivalSession {
        let bytes = try shopFixtureBytes()
        let transport = HostedShopTransport(scenario: .populated, offers: bytes.offers, catalogue: bytes.catalogue)
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let payload = try await session.catalog()
        let titles = payload.catalog.songs.map(\.title)
        #expect(fixtureTitles.allSatisfy(titles.contains), "fixture catalogue: \(titles)")
        return session
    }

    /// Storage with Reduce Motion on, so rotating demos hold still between captures.
    static func storage() throws -> (UserDefaults, String) {
        let name = "fst-first-run-songs-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: name))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        return (storage, name)
    }

    /// The slide with `id` on `page`.
    static func slide(_ page: FirstRunPageKey, _ id: String) throws -> FirstRunSlide {
        try #require(FirstRunCatalog.slides(for: page).first { $0.id == id }, "\(id) in the \(page) catalog")
    }

    /// Names of every element (or element-like node) carrying forbidden text.
    static func leaks(_ nodes: [MacAXNode]) -> [String] {
        nodes.filter { node in
            forbiddenText.contains { text in
                [node.label, node.title, node.value, node.help].contains { $0.contains(text) }
            }
        }.map(\.description)
    }

    // MARK: - Wrapper states

    /// The demos' song source hands placeholders to content without a session and the
    /// fixture catalogue's songs once it loads, so the demo checks below see both states.
    @Test func catalogueSongsSwitchFromPlaceholdersToCatalogueSongs() async throws {
        let session = try await Self.liveSession()
        let (storage, name) = try Self.storage()
        defer { storage.removePersistentDomain(forName: name) }
        let size = CGSize(width: 390, height: 120)
        for live in [false, true] {
            let host = nativeHostedView(
                FirstRunCatalogueSongs(count: 2) { songs, _ in
                    Text(songs.map(\.title).joined(separator: " | "))
                }
                .environment(\.firstRunSession, live ? session : nil)
                .defaultAppStorage(storage)
                .frame(width: size.width, height: size.height),
                size: size
            )
            let window = nativeHostedWindow(host, size: size)
            defer { window.orderOut(nil) }
            let expected = live ? Self.fixtureTitles : ["Placeholder"]
            try await nativeHostedSettle(host, untilText: expected)
            let text = nativeHostedAccessibility(host)
            #expect(expected.allSatisfy(text.contains), "\(live ? "live" : "placeholder"): \(text)")
            if !live {
                #expect(!Self.fixtureTitles.contains(where: text.contains), "no session shows no catalogue song")
            }
        }
    }

    // MARK: - Demos stay decorative

    /// Every song demo, with placeholder rows and with real catalogue rows, exposes nothing
    /// to VoiceOver: no element at all, so no placeholder text, song title or artist is read
    /// and nothing in the picture is focusable. The live render differs from the placeholder
    /// render, proving the catalogue state was reached.
    @Test func songDemosExposeNoElementsWithPlaceholdersOrCatalogueSongs() async throws {
        let session = try await Self.liveSession()
        let (storage, name) = try Self.storage()
        defer { storage.removePersistentDomain(forName: name) }
        let size = CGSize(width: 390, height: 360)
        for (page, id) in Self.songDemoSlides {
            let slide = try Self.slide(page, id)
            var signatures: [Int] = []
            for live in [false, true] {
                let host = nativeHostedView(
                    FirstRunDemoContent(page: page, slide: slide)
                        .environment(\.firstRunSession, live ? session : nil)
                        .defaultAppStorage(storage)
                        .padding(20)
                        .frame(width: size.width, height: size.height)
                        .background(BrandTokens.cardBackground)
                        .preferredColorScheme(.dark),
                    size: size
                )
                let window = nativeHostedWindow(host, size: size)
                defer { window.orderOut(nil) }
                // Placeholders: wait until the rows have painted (two blank frames before the
                // stagger would otherwise count as settled). Live: wait until the picture
                // differs from the placeholder one, i.e. catalogue rows replaced them (artwork
                // fails in this fixture, so a live art-only grid may be blank).
                let placeholder = signatures.first
                let image = try await nativeHostedSettle(host, animationGrace: .milliseconds(600)) {
                    guard let image = try? nativeHostedImage(host) else { return false }
                    if let placeholder { return nativeHostedSignature(image) != placeholder }
                    let content = nativeHostedContent(image)
                    return content.inkFraction > 0.0005 || content.nonBackgroundFraction > 0.01
                }
                signatures.append(nativeHostedSignature(image))
                let nodes = macAccessibilityTree(host)
                macAccessibilityDump(nodes, name: "first-run-\(id)-\(live ? "live" : "placeholder")")
                // The hosting view itself is the only element a decorative picture may have.
                let elements = nodes.filter { $0.isElement && $0.subrole != "AXHostingView" }
                #expect(elements.isEmpty, "\(id) (\(live ? "live" : "placeholder")) exposes \(elements.map(\.description))")
                #expect(Self.leaks(nodes).isEmpty, "\(id) (\(live ? "live" : "placeholder")) leaks \(Self.leaks(nodes))")
            }
            #expect(signatures.count == 2 && signatures[0] != signatures[1], "\(id) never left its placeholder rows")
        }
    }

    // MARK: - Carousel: name, reading order, targets, text scaling

    /// Host a two-slide carousel whose first slide is a song demo, over the live fixture
    /// catalogue, at a Dynamic Type size.
    ///
    /// - Parameters:
    ///   - session: Session with the fixture catalogue loaded.
    ///   - storage: Reduce Motion storage.
    ///   - typeSize: Dynamic Type size for the whole sheet.
    /// - Returns: The settled host, its window and the slides.
    static func hostCarousel(
        session: FestivalSession, storage: UserDefaults, typeSize: DynamicTypeSize
    ) async throws -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow, [FirstRunSlide]) {
        let slides = try [Self.slide(.statistics, "statistics-top-songs"), Self.slide(.statistics, "statistics-overview")]
        var viewing = FirstRunViewing(slides: slides)
        let size = CGSize(width: 390, height: 760)
        let host = nativeHostedView(
            AnyView(
                FirstRunCarouselView(
                    page: .statistics, slides: slides,
                    viewing: Binding(get: { viewing }, set: { viewing = $0 })
                ) {}
                .environment(\.firstRunSession, session)
                .defaultAppStorage(storage)
                .environment(\.dynamicTypeSize, typeSize)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host, untilText: [slides[0].title, "Page", "Next", "Skip"])
        let entrance = FirstRunMotion.textDelays(slideId: slides[0].id).description + FirstRunDemoTiming.fadeSeconds + 0.3
        try await Task.sleep(for: .seconds(entrance))
        try await nativeHostedSettle(host, untilText: [slides[0].title, "Page", "Next", "Skip"])
        return (host, window, slides)
    }

    /// The slide is one element named by its title and description only; the song demo
    /// adds no words to it and nothing else in the sheet reads a placeholder or a song.
    /// The slide reads before the page dots, then Next, then Skip, and both actions keep
    /// full-size targets (``assertTargets(in:)``).
    @Test func carouselReadsTheSlideNotItsSongsThenTheActions() async throws {
        let session = try await Self.liveSession()
        let (storage, name) = try Self.storage()
        defer { storage.removePersistentDomain(forName: name) }
        let (host, window, slides) = try await Self.hostCarousel(session: session, storage: storage, typeSize: .large)
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "first-run-carousel-songs-large")
        try Self.assertSlideAndOrder(nodes, slide: slides[0])

        try Self.assertTargets(in: host)
    }

    /// At the largest accessibility text size the slide keeps its whole name, still reads
    /// before the actions, and Next and Skip stay on screen with full-size targets.
    @Test func carouselKeepsSlideTextAndActionsReachableAtAccessibilitySizes() async throws {
        let session = try await Self.liveSession()
        let (storage, name) = try Self.storage()
        defer { storage.removePersistentDomain(forName: name) }
        let (host, window, slides) = try await Self.hostCarousel(
            session: session, storage: storage, typeSize: .accessibility5
        )
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "first-run-carousel-songs-ax5")
        try Self.assertSlideAndOrder(nodes, slide: slides[0])

        try Self.assertTargets(in: host)
    }

    /// Next and Skip are on screen, span the sheet's width and meet the platform's control
    /// size: Skip's row is at least 44 pt (``FirstRunControls/minimumHeight``) everywhere;
    /// Next is the system large button, at least 28 pt on the Mac (HIG Accessibility, macOS
    /// default) and checked at 44 pt on iPhone by
    /// `FirstRunJourneyTests.testSongDemoSlideAccessibleAtLargestText`.
    ///
    /// - Parameter host: The hosted carousel.
    /// - Throws: A missing control.
    static func assertTargets(in host: NSView) throws {
        let minimum: [String: CGFloat] = ["fst.first-run.next": 28, "fst.first-run.skip": 44]
        for (id, height) in minimum {
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: host), "\(id) frame")
            #expect(frame.height >= height - 0.5, "\(id) is at least \(height) pt tall: \(frame)")
            #expect(frame.width >= host.bounds.width / 2, "\(id) spans the sheet: \(frame)")
            #expect(host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(id) stays on screen: \(frame)")
        }
    }

    /// Shared carousel checks: the slide element's name, no leaks, reading order.
    ///
    /// - Parameters:
    ///   - nodes: The hosted carousel's accessibility tree.
    ///   - slide: The visible (song demo) slide.
    /// - Throws: A missing element.
    static func assertSlideAndOrder(_ nodes: [MacAXNode], slide: FirstRunSlide) throws {
        let order = nodes.filter(\.isElement)
        let dump = order.map(\.description).joined(separator: "\n")
        let slideIndex = try #require(order.firstIndex { $0.spokenName.hasPrefix("\(slide.title). ") }, "slide element in\n\(dump)")
        let element = order[slideIndex]
        #expect(element.spokenName == "\(slide.title). \(FirstRunCopy.mac(slide.description))", "\(element)")
        #expect(Self.leaks(nodes).isEmpty, "the demo's songs are not read: \(Self.leaks(nodes))")
        #expect(macAccessibilityFindings(nodes) == [], "\(dump)")

        let dots = try #require(order.firstIndex { $0.identifier == "fst.first-run.dots" }, "dots in\n\(dump)")
        let next = try #require(order.firstIndex { $0.identifier == "fst.first-run.next" }, "Next in\n\(dump)")
        let skip = try #require(order.firstIndex { $0.identifier == "fst.first-run.skip" }, "Skip in\n\(dump)")
        #expect(slideIndex < dots && dots < next && next < skip, "slide, dots, Next, Skip: \([slideIndex, dots, next, skip])")
        #expect(order[dots].spokenName == "Page", "\(order[dots])")
    }
}
#endif
