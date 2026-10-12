#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - First-run real-control demos and web motion accessibility (issue #380, backfilled by #498)

/// Issue #380 rebuilt the first-run demos from the pages' real controls: the Songs Sort and
/// Filter sheets, a real system tab bar, Player History's sort sheet, Suggestions' filter
/// sheet, the Profile Select Player button, View All, the Song Details Item Shop button and
/// paths. It also ported the web's motion: rows cascade in, the title and description fade
/// up after them, the Suggestions infinite scroll glides behind 36 pt edge fades, and Skip
/// became a borderless accent-tinted button. The #401/#402 checks cover the song and rotating
/// demos; these hosted checks pin the rest on the shared SwiftUI every Apple platform runs:
/// - every catalogue demo exposes nothing to VoiceOver, real buttons and toggles included
///   (HIG VoiceOver: "Exclude purely decorative images that convey no useful or actionable
///   information");
/// - in the carousel, a slide whose demo holds a real control still reads as one text element
///   named by its title and description, before the page dots, Next and Skip;
/// - system or in-app Reduce Motion shows the entrance at rest and holds the glide still
///   (HIG Accessibility: "When Reduce Motion is on, reduce automatic and repetitive
///   animation"; load-transition R6);
/// - Reduce Transparency, Less Transparency, Increase Contrast and More Contrast make the
///   glide's fades hard edges (scroll-edge R7);
/// - Skip's accent text keeps WCAG AA 4.5:1 on the sheet (HIG Accessibility contrast table).
@MainActor
@Suite(.serialized)
struct FirstRunNativeDemosAccessibilityTests {
    // MARK: - Fixture

    /// One catalogue slide, for parameterized tests.
    struct CatalogueSlide: Sendable, CustomTestStringConvertible {
        let page: FirstRunPageKey
        let id: String

        var testDescription: String { id }
    }

    /// Every slide the catalogue declares, on every page.
    nonisolated static let allSlides: [CatalogueSlide] = FirstRunPageKey.allCases.flatMap { page in
        FirstRunCatalog.slides(for: page).map { CatalogueSlide(page: page, id: $0.id) }
    }

    /// Slides whose demo embeds a real interactive control since #380 (a sheet, tab bar,
    /// button or action label).
    nonisolated static let realControlSlides: [CatalogueSlide] = [
        (FirstRunPageKey.songs, "songs-sort"), (.songs, "songs-navigation"), (.songs, "songs-filter"),
        (.songInfo, "songinfo-view-all"), (.songInfo, "songinfo-paths"), (.songInfo, "songinfo-shop-button"),
        (.playerHistory, "playerhistory-sort"), (.statistics, "statistics-select-profile"),
        (.suggestions, "suggestions-global-filter"), (.suggestions, "suggestions-instrument-filter"),
    ].map { CatalogueSlide(page: $0.0, id: $0.1) }

    /// The slide with `id` on `page`.
    static func slide(_ page: FirstRunPageKey, _ id: String) throws -> FirstRunSlide {
        try #require(FirstRunCatalog.slides(for: page).first { $0.id == id }, "\(id) in the \(page) catalog")
    }

    /// Isolated app storage with the in-app accessibility settings as given.
    static func storage(
        reduceMotion: Bool, lessTransparency: Bool = false, moreContrast: Bool = false
    ) throws -> (UserDefaults, String) {
        let name = "fst-first-run-native-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: name))
        storage.set(reduceMotion, forKey: "fst.accessibility.reduceMotion")
        storage.set(lessTransparency, forKey: "fst.accessibility.lessTransparency")
        storage.set(moreContrast, forKey: "fst.accessibility.moreContrast")
        return (storage, name)
    }

    /// Seconds after which a slide's whole entrance (demo cascade, title and description
    /// fades) has finished, with margin for a busy host.
    static func entranceSeconds(_ id: String) -> Double {
        FirstRunMotion.textDelays(slideId: id).description + FirstRunDemoTiming.fadeSeconds + 0.4
    }

    /// Host one slide's demo as the visible demo, over the rotation fixture session.
    ///
    /// - Parameters:
    ///   - page: The slide's page.
    ///   - slide: The slide.
    ///   - session: Fixture session.
    ///   - storage: App settings.
    ///   - systemReduceMotion: System Reduce Motion.
    ///   - systemReduceTransparency: System Reduce Transparency.
    ///   - increaseContrast: System Increase Contrast.
    /// - Returns: The host and its window.
    static func hostDemo(
        _ page: FirstRunPageKey, _ slide: FirstRunSlide, session: FestivalSession, storage: UserDefaults,
        systemReduceMotion: Bool = false, systemReduceTransparency: Bool = false, increaseContrast: Bool = false
    ) -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow) {
        let size = CGSize(width: 390, height: 360)
        let host = nativeHostedView(
            AnyView(
                FirstRunDemoContent(page: page, slide: slide)
                    .environment(\.firstRunSession, session)
                    .environment(\.firstRunDemoActive, true)
                    .environment(\.scenePhase, .active)
                    .environment(\._accessibilityReduceMotion, systemReduceMotion)
                    .environment(\._accessibilityReduceTransparency, systemReduceTransparency)
                    .environment(\._colorSchemeContrast, increaseContrast ? .increased : .standard)
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

    /// Host a two-slide carousel whose first slide is `first`.
    ///
    /// - Parameters:
    ///   - page: The guide's page.
    ///   - first: The visible slide.
    ///   - session: Fixture session.
    ///   - storage: App settings.
    ///   - systemReduceMotion: System Reduce Motion.
    /// - Returns: The host, its window and the slides.
    static func hostCarousel(
        _ page: FirstRunPageKey, first: FirstRunSlide, session: FestivalSession, storage: UserDefaults,
        systemReduceMotion: Bool = false
    ) throws -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow, [FirstRunSlide]) {
        let other = try #require(
            FirstRunCatalog.slides(for: page).first { $0.id != first.id }
                ?? FirstRunCatalog.slides(for: .songs).first { $0.id != first.id }
        )
        let slides = [first, other]
        var viewing = FirstRunViewing(slides: slides)
        let size = CGSize(width: 390, height: 760)
        let host = nativeHostedView(
            AnyView(
                FirstRunCarouselView(
                    page: page, slides: slides,
                    viewing: Binding(get: { viewing }, set: { viewing = $0 })
                ) {}
                .environment(\.firstRunSession, session)
                .environment(\.scenePhase, .active)
                .environment(\._accessibilityReduceMotion, systemReduceMotion)
                .defaultAppStorage(storage)
                .frame(width: size.width, height: size.height)
                // The opaque sheet the guide draws under Reduce Transparency, so its white
                // text shows in the image.
                .background(BrandTokens.cardBackground)
                .preferredColorScheme(.dark)
            ),
            size: size
        )
        return (host, nativeHostedWindow(host, size: size), slides)
    }

    // MARK: - Every demo stays decorative

    /// Every catalogue demo, visible with motion allowed and past its whole entrance, exposes
    /// no element to VoiceOver: none of the real sheets, toggles, tab bar items, buttons or
    /// rows #380 put in the demos is reachable or focusable.
    @Test(arguments: allSlides)
    func everyDemoExposesNothing(_ entry: CatalogueSlide) async throws {
        let session = try await FirstRunDemoRotationAccessibilityTests.rotationSession()
        let (storage, name) = try Self.storage(reduceMotion: false)
        defer { storage.removePersistentDomain(forName: name) }
        let slide = try Self.slide(entry.page, entry.id)
        let (host, window) = Self.hostDemo(entry.page, slide, session: session, storage: storage)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, animationGrace: .milliseconds(600))
        try await Task.sleep(for: .seconds(Self.entranceSeconds(entry.id)))
        let reached = FirstRunDemoRotationAccessibilityTests.reachable(host).map(\.node.description)
        if !reached.isEmpty { macAccessibilityDump(macAccessibilityTree(host), name: "first-run-native-\(entry.id)") }
        #expect(reached.isEmpty, "\(entry.id) exposes \(reached)")
    }

    // MARK: - Carousel: real-control slides read as text

    /// In the carousel, each slide whose demo embeds a real control is one static-text element
    /// named by its title and description (the combined slide absorbs no button, toggle or tab
    /// from its demo), it reads before the page dots, Next and Skip, and nothing else in the
    /// sheet is reachable.
    @Test(arguments: realControlSlides)
    func realControlSlideReadsAsTextBeforeTheActions(_ entry: CatalogueSlide) async throws {
        let session = try await FirstRunDemoRotationAccessibilityTests.rotationSession()
        let (storage, name) = try Self.storage(reduceMotion: false)
        defer { storage.removePersistentDomain(forName: name) }
        let slide = try Self.slide(entry.page, entry.id)
        let (host, window, _) = try Self.hostCarousel(entry.page, first: slide, session: session, storage: storage)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: [slide.title, "Page", "Next", "Skip"])
        try await Task.sleep(for: .seconds(Self.entranceSeconds(entry.id)))

        let reached = FirstRunDemoRotationAccessibilityTests.reachable(host)
        let names = reached.map { $0.node.identifier.isEmpty ? $0.node.spokenName : "#\($0.node.identifier)" }
        let expected = "\(slide.title). \(FirstRunCopy.mac(slide.description))"
        let slideIndex = try #require(names.firstIndex(of: expected), "slide element in \(names)")
        let element = reached[slideIndex].node
        #expect(element.role == "AXStaticText", "\(entry.id) slide reads as text, not a control: \(element)")
        let actions = (reached[slideIndex].object.value(forKey: "accessibilityCustomActions") as? [Any]) ?? []
        #expect(actions.isEmpty, "\(entry.id) slide carries its demo's actions: \(actions)")
        let order = ["#fst.first-run.dots", "#fst.first-run.next", "#fst.first-run.skip"].map { names.firstIndex(of: $0) }
        #expect(order.allSatisfy { $0 != nil }, "\(entry.id): dots, Next and Skip reachable in \(names)")
        let indices = order.compactMap { $0 }
        #expect([slideIndex] + indices == ([slideIndex] + indices).sorted(), "\(entry.id): slide, dots, Next, Skip: \(names)")
        let extra = reached.indices.filter { index in
            let node = reached[index].node
            // The macOS carousel's unnamed page containers (tab group, page hosting view).
            let container = ["AXTabGroup", "AXGroup"].contains(node.role) && node.spokenName.isEmpty
            return !container && names[index] != expected && !names[index].hasPrefix("#fst.first-run.")
        }
        #expect(extra.isEmpty, "\(entry.id): the demo's controls reached VoiceOver: \(extra.map { reached[$0].node.description })")
        try FirstRunDemoSongsAccessibilityTests.assertTargets(in: host)
    }

    // MARK: - Reduce Motion: entrance at rest, glide held

    /// The two Reduce Motion sources.
    nonisolated static let reduceMotionSettings: [ReduceMotionSetting] = [.system, .app]

    /// System Reduce Motion or the app's own setting.
    enum ReduceMotionSetting: String, Sendable, CustomTestStringConvertible {
        case system, app

        var testDescription: String { rawValue }
    }

    /// The carousel's first picture of a slide with the longest web cascade (Leaderboards Your
    /// Rank: 7 row steps, then the title and description) against its picture after the whole
    /// entrance. With motion allowed the first picture has not faded in yet; with system or
    /// in-app Reduce Motion it is already the picture at rest, so nothing moves.
    @Test(arguments: [ReduceMotionSetting?.none] + reduceMotionSettings.map { Optional($0) })
    func reduceMotionShowsTheEntranceAtRest(_ setting: ReduceMotionSetting?) async throws {
        let session = try await FirstRunDemoRotationAccessibilityTests.rotationSession()
        let (storage, name) = try Self.storage(reduceMotion: setting == .app)
        defer { storage.removePersistentDomain(forName: name) }
        let slide = try Self.slide(.leaderboards, "leaderboards-your-rank")
        let (host, window, _) = try Self.hostCarousel(
            .leaderboards, first: slide, session: session, storage: storage, systemReduceMotion: setting == .system
        )
        defer { window.orderOut(nil) }
        // Synchronous, before any run-loop turn: the entrance has not started.
        let first = try nativeHostedImage(host)
        let label = setting?.rawValue ?? "motion allowed"
        // The title and description band: below the demo (its frame ends by 383 pt; its card
        // material settles a shade after the first frame, which is not motion) and above the
        // page dots, inside the sheet's edges.
        let dots = try #require(nativeHostedAccessibilityFrame("fst.first-run.dots", in: host), "dots frame")
        let text = CGRect(x: 8, y: 390, width: host.bounds.width - 16, height: dots.minY - 4 - 390)
        func ink(_ image: CGImage) throws -> Double {
            nativeHostedContent(try Self.crop(image, to: text, in: host.bounds.size)).inkFraction
        }
        let firstInk = try ink(first)
        // The resting text, judged by what it draws rather than when a capture lands.
        let rest = try await nativeHostedSettle(host, animationGrace: .seconds(Self.entranceSeconds(slide.id))) {
            ((try? nativeHostedImage(host)).flatMap { try? ink($0) } ?? 0) > 0.01
        }
        let restInk = try ink(rest)
        #expect(restInk > 0.01, "the title and description show after the entrance (\(label)): ink \(restInk)")
        if setting == nil {
            #expect(firstInk < restInk / 4, "the text fades in with motion allowed: ink \(firstInk) → \(restInk)")
        } else {
            #expect(
                abs(firstInk - restInk) <= restInk * 0.02,
                "the title or description faded under Reduce Motion (\(label)): ink \(firstInk) → \(restInk)"
            )
        }
        let reached = FirstRunDemoRotationAccessibilityTests.reachable(host).map(\.node.spokenName)
        #expect(
            reached.contains("\(slide.title). \(FirstRunCopy.mac(slide.description))"),
            "the slide reads whole after its entrance (\(label)): \(reached)"
        )
    }

    /// The Suggestions infinite-scroll demo glides with motion allowed and holds the top of
    /// its stack under system or in-app Reduce Motion; it stays decorative either way.
    @Test(arguments: [ReduceMotionSetting?.none] + reduceMotionSettings.map { Optional($0) })
    func reduceMotionHoldsTheInfiniteScroll(_ setting: ReduceMotionSetting?) async throws {
        let session = try await FirstRunDemoRotationAccessibilityTests.rotationSession()
        let (storage, name) = try Self.storage(reduceMotion: setting == .app)
        defer { storage.removePersistentDomain(forName: name) }
        let slide = try Self.slide(.suggestions, "suggestions-infinite-scroll")
        let (host, window) = Self.hostDemo(
            .suggestions, slide, session: session, storage: storage, systemReduceMotion: setting == .system
        )
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, animationGrace: .milliseconds(600))
        try await Task.sleep(for: .seconds(Self.entranceSeconds(slide.id)))
        let before = try await nativeHostedSettle(host, animationGrace: .milliseconds(400))
        var deadline = NativeHostedEvidenceDeadline(limit: .seconds(12))
        try await deadline.awaitResponsiveMainActor()
        // 1.5 s at the web's 30 pt/s is a 45 pt glide.
        try await deadline.sleep(for: .milliseconds(1500))
        let after = try nativeHostedImage(host)
        if setting == nil {
            FirstRunDemoRotationAccessibilityTests.expectSwapped(
                nativeHostedSignature(before) != nativeHostedSignature(after), deadline: deadline,
                "the infinite scroll never glided with motion allowed"
            )
        } else {
            #expect(
                nativeHostedSignature(before) == nativeHostedSignature(after),
                "the infinite scroll moved under Reduce Motion (\(setting?.rawValue ?? ""))"
            )
        }
        #expect(FirstRunDemoRotationAccessibilityTests.reachable(host).isEmpty, "the infinite scroll stays decorative")
    }

    // MARK: - Hard edges for transparency and contrast settings

    /// Settings that turn a scroll-edge ramp into a hard edge (scroll-edge R7).
    enum HardEdgeSetting: String, Sendable, CaseIterable, CustomTestStringConvertible {
        case systemReduceTransparency, appLessTransparency, systemIncreaseContrast, appMoreContrast

        var testDescription: String { rawValue }
    }

    /// Render the held infinite-scroll demo (Reduce Motion, so the stack rests at the top: no
    /// top fade, a 36 pt fade at the bottom where cards are hidden).
    ///
    /// - Parameter setting: A hard-edge setting, or nil for the default fades.
    /// - Returns: The rendered demo and its host's size.
    static func heldInfiniteScroll(_ setting: HardEdgeSetting?) async throws -> (CGImage, CGSize) {
        let session = try await FirstRunDemoRotationAccessibilityTests.rotationSession()
        let (storage, name) = try Self.storage(
            reduceMotion: true, lessTransparency: setting == .appLessTransparency, moreContrast: setting == .appMoreContrast
        )
        defer { storage.removePersistentDomain(forName: name) }
        let slide = try Self.slide(.suggestions, "suggestions-infinite-scroll")
        let (host, window) = Self.hostDemo(
            .suggestions, slide, session: session, storage: storage,
            systemReduceTransparency: setting == .systemReduceTransparency,
            increaseContrast: setting == .systemIncreaseContrast
        )
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(host, animationGrace: .milliseconds(800))
        #expect(FirstRunDemoRotationAccessibilityTests.reachable(host).isEmpty, "decorative (\(setting?.rawValue ?? "default"))")
        return (image, host.bounds.size)
    }

    /// The part of a host's image inside `rect` (host points, top left).
    static func crop(_ image: CGImage, to rect: CGRect, in size: CGSize) throws -> CGImage {
        let scale = CGFloat(image.height) / size.height
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        return try #require(image.cropping(to: pixels.integral), "crop \(rect)")
    }

    /// Hash of an image's own pixels. A cropped `CGImage` may share its parent's data
    /// provider, so ``nativeHostedSignature(_:)`` of a crop can hash the whole capture.
    static func pixelSignature(_ image: CGImage) -> Int {
        var hasher = Hasher()
        NativeHostedPixels(image).withBytes { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
        return hasher.finalize()
    }

    /// Signature of the band `points` tall at the top or bottom of the demo's viewport.
    static func band(_ image: CGImage, size: CGSize, bottom: Bool, points: CGFloat) throws -> Int {
        let scale = CGFloat(image.height) / size.height
        // The demo sits inside 20 pt of padding.
        let inset: CGFloat = 20
        let y = bottom ? size.height - inset - points : inset
        let rect = CGRect(x: inset * scale, y: y * scale, width: (size.width - inset * 2) * scale, height: points * scale)
        let crop = try #require(image.cropping(to: rect.integral), "crop \(rect)")
        return pixelSignature(crop)
    }

    /// Each hard-edge setting removes the 36 pt fade at the bottom of the infinite-scroll
    /// viewport: the bottom band differs from the default render while the top band, which
    /// never fades at rest, is unchanged, so the difference is the edge, not a restyled card.
    @Test func transparencyAndContrastSettingsMakeTheInfiniteScrollEdgeHard() async throws {
        let ramp = CGFloat(FirstRunAutoScroll.edgeFade)
        let (normal, size) = try await Self.heldInfiniteScroll(nil)
        let normalBottom = try Self.band(normal, size: size, bottom: true, points: ramp)
        let normalTop = try Self.band(normal, size: size, bottom: false, points: ramp)
        for setting in HardEdgeSetting.allCases {
            let (image, _) = try await Self.heldInfiniteScroll(setting)
            let bottom = try Self.band(image, size: size, bottom: true, points: ramp)
            #expect(bottom != normalBottom, "\(setting.rawValue) keeps the bottom fade")
            #expect(try Self.band(image, size: size, bottom: false, points: ramp) == normalTop,
                    "\(setting.rawValue) changed the unfaded top")
        }
    }

    // MARK: - Skip contrast

    /// WCAG relative luminance of an sRGB colour.
    static func luminance(_ color: Color) throws -> Double {
        let rgb = try #require(NSColor(color).usingColorSpace(.sRGB), "sRGB \(color)")
        func channel(_ value: CGFloat) -> Double {
            let c = Double(value)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
    }

    /// WCAG contrast ratio of two colours.
    static func contrast(_ a: Color, _ b: Color) throws -> Double {
        let (la, lb) = (try luminance(a), try luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Skip is regular 17 pt body text in ``AccentText/blue`` since #380. On the guide's opaque
    /// sheet (``BrandTokens/cardBackground``, used under Reduce Transparency, Less Transparency
    /// and More Contrast) and on the darkest app background it keeps WCAG AA 4.5:1 for text up
    /// to 17 pt (HIG Accessibility contrast table), unlike the brand fill blue it replaced as
    /// a text colour.
    @Test func skipAccentTextKeepsAAContrastOnTheSheet() throws {
        for background in [BrandTokens.cardBackground, BrandTokens.appBackground] {
            let ratio = try Self.contrast(AccentText.blue, background)
            #expect(ratio >= 4.5, "Skip text contrast \(ratio):1 on \(background)")
        }
    }
}
#endif
