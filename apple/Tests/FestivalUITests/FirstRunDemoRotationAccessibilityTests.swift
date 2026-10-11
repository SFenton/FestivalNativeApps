#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - First-run demo rotation accessibility (issue #27, backfilled by #402)

/// Issue #27 made twelve first-run demos swap to new data on the web's clock (fade out, replace
/// while hidden, fade in; ``FirstRunDemoSwap``). The demos are decorative pictures of the app,
/// so the slide's title and description stay its one accessible element while rows change.
/// These hosted checks let the demos rotate (the #26/#401 checks hold them still) and pin, on
/// every Apple platform the shared SwiftUI carousel runs on:
/// - every rotating demo exposes no element and no song, rival or card text before, during or
///   after a swap (HIG VoiceOver: "Exclude purely decorative images that convey no useful or
///   actionable information");
/// - in the carousel, a swap leaves the slide's name, role and frame, the reading order and
///   the Next and Skip targets unchanged at Large and AX5, so nothing moves under the
///   VoiceOver cursor;
/// - system or in-app Reduce Motion holds every rotating demo on its first state past its swap
///   interval (HIG Accessibility: "When Reduce Motion is on, reduce automatic and repetitive
///   animation"; load-transition R6).
@MainActor
struct FirstRunDemoRotationAccessibilityTests {
    // MARK: - Fixture

    /// One rotating demo slide and its swap interval.
    struct RotatingSlide: Sendable, CustomTestStringConvertible {
        let page: FirstRunPageKey
        let id: String
        let interval: Duration

        var testDescription: String { id }
    }

    /// Every slide whose demo rotates (`.agents/controls/first-run/ios.md`, "Data-swap rotation").
    nonisolated static let rotatingSlides: [RotatingSlide] = [
        (FirstRunPageKey.songs, "songs-song-list"), (.songs, "songs-icons"), (.songs, "songs-metadata"),
        (.statistics, "statistics-top-songs"), (.songInfo, "songinfo-bar-select"),
        (.suggestions, "suggestions-category-card"), (.leaderboards, "leaderboards-experimental-metrics"),
        (.compete, "compete-hub"), (.compete, "compete-rivals"),
        (.rivals, "rivals-overview"), (.rivals, "rivals-instruments"), (.rivals, "rivals-detail"),
    ].map { page, id in
        RotatingSlide(
            page: page, id: id,
            interval: id == "songinfo-bar-select" ? FirstRunDemoTiming.barSelectInterval : FirstRunDemoTiming.swapInterval
        )
    }

    /// Songs in the synthetic rotation catalogue: more than any demo shows, so catalogue demos
    /// have songs to swap in (the checked-in two-song fixture cannot rotate).
    static let rotationSongCount = 12

    /// Text no accessibility node may carry: demo songs, placeholders, rivals and card titles.
    static let forbiddenText: [String] = ["Rotation Song", "Synthetic Quartet", "Placeholder"]
        + (FirstRunDemoPool.rivalsAbove + FirstRunDemoPool.rivalsBelow).map(\.name)
        + FirstRunDemoPool.rivalDetailCategories.map(\.title)
        + FirstRunSuggestionsCategoryCardDemo.templates.map(\.title)

    /// A synthetic `/api/songs` envelope of ``rotationSongCount`` songs with artwork paths.
    static func rotationCatalogue() throws -> Data {
        let songs: [[String: Any]] = (1...rotationSongCount).map { index in
            let number = String(format: "%02d", index)
            return [
                "songId": "rotation-\(number)", "title": "Rotation Song \(number)",
                "artist": "Synthetic Quartet", "year": 2026,
                "albumArt": "/__fixture__/art/rotation-\(number).png",
                "difficulty": ["guitar": index % 7, "bass": (index + 2) % 7, "drums": (index + 4) % 7, "vocals": 1],
            ]
        }
        return try JSONSerialization.data(withJSONObject: ["count": songs.count, "currentSeason": 9, "songs": songs])
    }

    /// A session whose catalogue is the synthetic rotation catalogue, already loaded, so demos
    /// read it from the session's cache the moment they mount.
    ///
    /// - Returns: A session over the in-memory fixture transport (no live service).
    /// - Throws: Missing fixture or a failed fixture read.
    static func rotationSession() async throws -> FestivalSession {
        let bytes = try shopFixtureBytes()
        let transport = HostedShopTransport(scenario: .populated, offers: bytes.offers, catalogue: try rotationCatalogue())
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let payload = try await session.catalog()
        #expect(payload.catalog.songs.count == rotationSongCount)
        return session
    }

    /// Isolated app storage with the in-app Reduce Motion setting as given.
    static func storage(reduceMotion: Bool) throws -> (UserDefaults, String) {
        let name = "fst-first-run-rotation-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: name))
        storage.set(reduceMotion, forKey: "fst.accessibility.reduceMotion")
        return (storage, name)
    }

    /// The slide with `id` on `page`.
    static func slide(_ page: FirstRunPageKey, _ id: String) throws -> FirstRunSlide {
        try #require(FirstRunCatalog.slides(for: page).first { $0.id == id }, "\(id) in the \(page) catalog")
    }

    /// Nodes carrying forbidden text.
    static func leaks(_ nodes: [MacAXNode]) -> [String] {
        nodes.filter { node in
            forbiddenText.contains { text in
                [node.label, node.title, node.value, node.help].contains { $0.contains(text) }
            }
        }.map(\.description)
    }

    /// One element VoiceOver can reach, with the object behind it (for its frame).
    struct Reached {
        let node: MacAXNode
        let object: NSObject
    }

    /// The elements VoiceOver reaches from `host` through `accessibilityChildren` in navigation
    /// order, below the hosting view itself. ``macAccessibilityTree(_:navigationOrder:)`` also
    /// descends AppKit subviews, where an artwork tile's loading `ProgressView` (shown for a
    /// moment after each swap) is backed by an `NSProgressIndicator` the hosting view never
    /// lists as a child (the same distinction `ReloadGateAccessibilityTests.reachable` draws).
    ///
    /// - Parameter host: The hosted view.
    /// - Returns: Reachable elements, depth first, in reading order.
    static func reachable(_ host: NSView) -> [Reached] {
        var found: [Reached] = []
        var seen = Set<ObjectIdentifier>()
        func read(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }
        func walk(_ node: Any, depth: Int) {
            guard depth < 90, let object = node as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            if depth > 0, (read(object, "isAccessibilityElement") as? Bool) == true {
                found.append(Reached(node: MacAXNode(
                    depth: depth, role: nativeHostedAccessibilityString(object, "accessibilityRole"),
                    subrole: nativeHostedAccessibilityString(object, "accessibilitySubrole"),
                    label: nativeHostedAccessibilityString(object, "accessibilityLabel"),
                    title: nativeHostedAccessibilityString(object, "accessibilityTitle"),
                    value: nativeHostedAccessibilityString(object, "accessibilityValue"),
                    identifier: nativeHostedAccessibilityString(object, "accessibilityIdentifier"),
                    selected: false, help: "", isElement: true
                ), object: object))
            }
            let ordered = read(object, "accessibilityChildrenInNavigationOrder") as? [Any]
            for child in ordered ?? (read(object, "accessibilityChildren") as? [Any]) ?? [] {
                walk(child, depth: depth + 1)
            }
        }
        walk(host, depth: 0)
        return found
    }

    /// Host one demo as the visible slide's demo (`firstRunDemoActive`), over the rotation
    /// session.
    static func hostDemo(
        _ rotating: RotatingSlide, session: FestivalSession, storage: UserDefaults, systemReduceMotion: Bool
    ) throws -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow) {
        let slide = try Self.slide(rotating.page, rotating.id)
        let size = CGSize(width: 390, height: 360)
        let host = nativeHostedView(
            AnyView(
                FirstRunDemoContent(page: rotating.page, slide: slide)
                    .environment(\.firstRunSession, session)
                    .environment(\.firstRunDemoActive, true)
                    .environment(\._accessibilityReduceMotion, systemReduceMotion)
                    .defaultAppStorage(storage)
                    .padding(20)
                    .frame(width: size.width, height: size.height)
                    .background(BrandTokens.cardBackground)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        return (host, nativeHostedWindow(host, size: size))
    }

    /// Time past one swap interval that covers both fades and a busy parallel run's lag.
    static func pastOneSwap(_ interval: Duration) -> Duration {
        interval + FirstRunDemoTiming.fade * 2 + .milliseconds(600)
    }

    /// The longest a sampling loop waits, in wall-clock time, for its first swap.
    static let swapDeadline: Duration = .seconds(20)

    /// Expect that the sampled demo swapped. A swap is timer-driven animation, so on a host
    /// whose shared main actor was starved (`apple-ci` ran 2 samples in 20 s) its absence
    /// proves nothing and is an intermittent known issue (``NativeHostedEvidenceDeadline``,
    /// as in `CompeteRenderTests` and `SelectedRowRevealHostedTests`); on a responsive host
    /// it fails. The decorative-exposure checks stay strict either way.
    ///
    /// - Parameters:
    ///   - swapped: Whether any sample differed from the first picture.
    ///   - deadline: The sampling loop's deadline, with its recorded poll lag.
    ///   - message: What did not swap.
    static func expectSwapped(
        _ swapped: Bool, deadline: NativeHostedEvidenceDeadline, _ message: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard !swapped else { return }
        if let starved = deadline.starved {
            withKnownIssue("Starved host (\(starved)): its demo timers can't show a swap", isIntermittent: true) {
                Issue.record("\(message)", sourceLocation: sourceLocation)
            }
        } else {
            Issue.record("\(message)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Demos stay decorative while they rotate

    /// Each rotating demo, visible with motion allowed, is sampled every 150 ms through at least
    /// one swap: no sample exposes an element (beyond the hosting view) or any demo text, so the
    /// fading rows, the swapped-in rows and the rows fading back are all invisible to VoiceOver.
    /// The picture changing proves a swap happened while sampling.
    @Test(arguments: rotatingSlides)
    func rotatingDemoExposesNothingThroughASwap(_ rotating: RotatingSlide) async throws {
        let session = try await Self.rotationSession()
        let (storage, name) = try Self.storage(reduceMotion: false)
        defer { storage.removePersistentDomain(forName: name) }
        let (host, window) = try Self.hostDemo(rotating, session: session, storage: storage, systemReduceMotion: false)
        defer { window.orderOut(nil) }
        let first = try await nativeHostedSettle(host, animationGrace: .milliseconds(600))

        let clock = ContinuousClock()
        var deadline = NativeHostedEvidenceDeadline(limit: Self.swapDeadline)
        try await deadline.awaitResponsiveMainActor()
        let minimum = clock.now + Self.pastOneSwap(rotating.interval)
        var samples = 0
        var swapped = false
        var exposed: [String] = []
        var leaked: [String] = []
        while clock.now < minimum || (!swapped && !deadline.isExpired) {
            try await deadline.sleep(for: .milliseconds(150))
            let image = try nativeHostedImage(host)
            swapped = swapped || nativeHostedSignature(image) != nativeHostedSignature(first)
            exposed += Self.reachable(host).map(\.node.description)
            leaked += Self.leaks(macAccessibilityTree(host))
            samples += 1
        }
        Self.expectSwapped(swapped, deadline: deadline, "\(rotating.id) never swapped in \(samples) samples")
        #expect(exposed.isEmpty, "\(rotating.id) exposed \(Set(exposed).sorted())")
        #expect(leaked.isEmpty, "\(rotating.id) leaked \(Set(leaked).sorted())")
    }

    // MARK: - Reduce Motion holds every rotating demo still

    /// With the system or the app's Reduce Motion on, every rotating demo, visible and over a
    /// catalogue it could rotate, stays on its first state past one swap interval and both
    /// fades (#380's rule, now checked for all twelve demos, not only bar select).
    @Test(arguments: rotatingSlides, [(system: true, app: false), (system: false, app: true)])
    func reduceMotionHoldsRotatingDemoStill(_ rotating: RotatingSlide, setting: (system: Bool, app: Bool)) async throws {
        let session = try await Self.rotationSession()
        let (storage, name) = try Self.storage(reduceMotion: setting.app)
        defer { storage.removePersistentDomain(forName: name) }
        let (host, window) = try Self.hostDemo(rotating, session: session, storage: storage, systemReduceMotion: setting.system)
        defer { window.orderOut(nil) }
        let before = try await nativeHostedSettle(host, animationGrace: .milliseconds(600))
        try await Task.sleep(for: Self.pastOneSwap(rotating.interval))
        let after = try nativeHostedImage(host)
        #expect(
            nativeHostedSignature(before) == nativeHostedSignature(after),
            "\(rotating.id) rotated under Reduce Motion (system \(setting.system), app \(setting.app))"
        )
        #expect(Self.reachable(host).isEmpty, "\(rotating.id) stays decorative")
    }

    // MARK: - Carousel: the slide reads the same across a swap

    /// What VoiceOver can reach in the carousel at one moment.
    struct CarouselReading: Equatable, CustomStringConvertible {
        /// Element names (identifier when set) in reading order.
        let order: [String]
        /// The slide element's name and role.
        let slide: String
        /// Frames of the slide and the guide's own controls (page dots, Next, Skip), whole points.
        let frames: [String: CGRect]

        var description: String { "\(order) | \(slide) | \(frames)" }

        @MainActor
        init(host: NSView, slide: FirstRunSlide) throws {
            let reached = FirstRunDemoRotationAccessibilityTests.reachable(host)
            order = reached.map { $0.node.identifier.isEmpty ? $0.node.spokenName : "#\($0.node.identifier)" }
            let element = try #require(
                reached.first { $0.node.spokenName.hasPrefix("\(slide.title). ") },
                "slide element in \(reached.map(\.node.description))"
            )
            self.slide = "\(element.node.role) '\(element.node.spokenName)'"
            var frames: [String: CGRect] = [:]
            frames["slide"] = nativeHostedAccessibilityFrame(of: element.object, in: host)?.integral
            for item in reached where item.node.identifier.hasPrefix("fst.first-run.") {
                frames[item.node.identifier] = nativeHostedAccessibilityFrame(of: item.object, in: host)?.integral
            }
            self.frames = frames
        }
    }

    /// The carousel on a rotating song demo (Statistics Top Songs, two rows per swap), with
    /// motion allowed, at Large and AX5: across at least one swap the slide stays one static
    /// text element named by its title and description only, the reading order (slide, page
    /// dots, Next, Skip) and every frame stay put, no demo text reaches VoiceOver, and Next and
    /// Skip keep full-size on-screen targets (``FirstRunDemoSongsAccessibilityTests/assertTargets(in:)``).
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func carouselSlideReadsTheSameAcrossASwap(_ typeSize: DynamicTypeSize) async throws {
        let session = try await Self.rotationSession()
        let (storage, name) = try Self.storage(reduceMotion: false)
        defer { storage.removePersistentDomain(forName: name) }
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
                .environment(\.scenePhase, .active)
                .environment(\._accessibilityReduceMotion, false)
                .environment(\.dynamicTypeSize, typeSize)
                .defaultAppStorage(storage)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: [slides[0].title, "Page", "Next", "Skip"])
        let entrance = FirstRunMotion.textDelays(slideId: slides[0].id).description + FirstRunDemoTiming.fadeSeconds + 0.3
        try await Task.sleep(for: .seconds(entrance))
        let first = try await nativeHostedSettle(host, animationGrace: .milliseconds(600))
        let baseline = try CarouselReading(host: host, slide: slides[0])
        #expect(
            baseline.slide == "AXStaticText '\(slides[0].title). \(FirstRunCopy.mac(slides[0].description))'",
            "\(baseline)"
        )
        let ordered = ["fst.first-run.dots", "fst.first-run.next", "fst.first-run.skip"].compactMap {
            baseline.order.firstIndex(of: "#\($0)")
        }
        let slideIndex = baseline.order.firstIndex { $0.hasPrefix("\(slides[0].title). ") }
        #expect(ordered.count == 3 && ordered == ordered.sorted(), "dots, Next, Skip in order: \(baseline.order)")
        #expect(slideIndex.map { $0 < (ordered.first ?? 0) } == true, "the slide reads first: \(baseline.order)")
        let framed = ["slide", "fst.first-run.dots", "fst.first-run.next", "fst.first-run.skip"]
        #expect(framed.allSatisfy { baseline.frames[$0].map { !$0.isEmpty } == true }, "\(baseline.frames)")

        let clock = ContinuousClock()
        var deadline = NativeHostedEvidenceDeadline(limit: Self.swapDeadline)
        try await deadline.awaitResponsiveMainActor()
        let minimum = clock.now + Self.pastOneSwap(FirstRunDemoTiming.swapInterval)
        var swapped = false
        var changes: [String] = []
        var leaked: [String] = []
        while clock.now < minimum || (!swapped && !deadline.isExpired) {
            try await deadline.sleep(for: .milliseconds(150))
            let image = try nativeHostedImage(host)
            swapped = swapped || nativeHostedSignature(image) != nativeHostedSignature(first)
            let reading = try CarouselReading(host: host, slide: slides[0])
            if reading != baseline { changes.append(reading.description) }
            leaked += Self.leaks(macAccessibilityTree(host))
        }
        Self.expectSwapped(swapped, deadline: deadline, "the Top Songs demo never swapped (\(typeSize))")
        #expect(changes.isEmpty, "a swap changed what VoiceOver reads (\(typeSize)): \(baseline) → \(changes.first ?? "")")
        #expect(leaked.isEmpty, "demo text reached VoiceOver (\(typeSize)): \(Set(leaked).sorted())")
        try FirstRunDemoSongsAccessibilityTests.assertTargets(in: host)
    }
}
#endif
