#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Paths switch accessibility (issue #70, backfilled by #430)

// #70 gave the Paths sheet the web `PathsModal` switch: the old image, table or error
// fades out, a spinner holds for its minimum, and the new chart fades in
// (`PathSwitchTransition`, unit tested in `PathSwitchTransitionTests`). These hosted
// checks (macOS host, `apple-ci`) pin what that switch exposes to VoiceOver, Voice
// Control and Dynamic Type, since the sheet is the same SwiftUI on iPhone, iPad, iPhone
// Duo and Mac: one named spinner per loading form and no stale chart behind it, the
// selectors still named and reachable, the activation cards reading in order after the
// reveal, a Retry that works from assistive technology, the spoken switch
// announcements, and Reduce Motion (system or in-app) swapping instantly while the
// spinner still holds for its minimum (pattern `load-transition` R2, R4, R6).

// MARK: - Fixture

/// Serves the synthetic Fixture Pulse path; reads can be held open or fail.
actor PathSwitchTransport: HTTPTransport {
    let text: Data
    let image: Data
    private var failingTextReads: Int
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// - Parameters:
    ///   - text: The original local schema-2 fixture, never a downloaded path.
    ///   - image: A generated one-color PNG, not game artwork.
    ///   - failingTextReads: How many text reads answer 404 before one succeeds.
    init(text: Data, image: Data, failingTextReads: Int = 0) {
        self.text = text
        self.image = image
        self.failingTextReads = failingTextReads
    }

    /// Hold every path read until ``release()``, so the spinner stays up.
    func hold() { held = true }

    /// Answer the held reads and stop holding.
    func release() {
        held = false
        waiting.forEach { $0.resume() }
        waiting = []
    }

    /// Public, keyless GETs only, for this song's Lead Expert chart.
    ///
    /// - Parameter request: The sheet's native request.
    /// - Returns: The publication, the text fixture, the PNG or a 404.
    /// - Throws: An unsafe or unexpected request.
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
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        guard url.query == "generationId=fixture-generation" else { throw FestivalAPIError.invalidPublication }
        if held { await withCheckedContinuation { waiting.append($0) } }
        switch url.path {
        case "/api/paths/fixture-pulse/Solo_Guitar/expert/data":
            if failingTextReads > 0 {
                failingTextReads -= 1
                return HTTPResult(status: 404, data: Data(), headers: ["X-FST-Publication-Id": "7"])
            }
            return HTTPResult(status: 200, data: text, headers: ["X-FST-Publication-Id": "7"])
        case "/api/paths/fixture-pulse/Solo_Guitar/expert":
            return HTTPResult(status: 200, data: image, headers: ["X-FST-Publication-Id": "7"])
        default:
            throw FestivalAPIError.invalidResource
        }
    }
}

/// A generated solid PNG (never game artwork).
private func switchPathPNG() throws -> Data {
    guard let context = CGContext(
        data: nil, width: 240, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw FestivalAPIError.invalidPathImage }
    context.setFillColor(CGColor(red: 0.95, green: 0.42, blue: 0.05, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 180))
    guard let image = context.makeImage() else { throw FestivalAPIError.invalidPathImage }
    let bytes = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)
    else { throw FestivalAPIError.invalidPathImage }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw FestivalAPIError.invalidPathImage }
    return bytes as Data
}

// MARK: - Tests

/// Accessibility of the Paths switch #70 added.
///
/// HIG VoiceOver: "be sure to keep labels current as interface and content change";
/// HIG Loading: "Keep it usable while loading"; HIG Accessibility (Motion): "When Reduce
/// Motion is on, reduce automatic and repetitive animation" and "Be cautious with
/// fast-moving and blinking effects".
@MainActor
@Suite(.serialized)
struct SongPathsSwitchAccessibilityTests {
    /// How a switch moves.
    enum Motion: String, CaseIterable, CustomTestStringConvertible {
        /// Fades on, no Reduce Motion.
        case animated
        /// System Reduce Motion.
        case systemReduceMotion
        /// Settings' in-app Reduce Motion (ignored by the sheet before #430).
        case appReduceMotion

        var testDescription: String { rawValue }
    }

    /// One hosted sheet in an offscreen window.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let transport: PathSwitchTransport
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// What VoiceOver reaches through accessibility children, after one layout pass.
        func reachable() -> [MacAXNode] {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            return ReloadGateAccessibilityTests.reachable(host)
        }

        /// The frame of the reachable element `node` (by identifier or name).
        func frame(_ node: MacAXNode) -> CGRect? {
            let element = nativeHostedAccessibilityElement(in: host) { object in
                node.identifier.isEmpty
                    ? nativeHostedAccessibilityString(object, "accessibilityLabel") == node.label
                    : nativeHostedAccessibilityString(object, "accessibilityIdentifier") == node.identifier
            }
            return element.flatMap { nativeHostedAccessibilityFrame(of: $0, in: host) }
        }
    }

    /// The selectors' identifiers and names, in reading order.
    static let selectors = [
        ("fst.paths.instrument", "Lead"), ("fst.paths.difficulty", "Expert"), ("fst.paths.display", "Text"),
    ]
    static let selectorIDs = selectors.map(\.0)

    /// Host the sheet for Fixture Pulse (Lead, Expert).
    ///
    /// - Parameters:
    ///   - display: The Settings default view.
    ///   - viewMode: The first View selection (Side by Side on a wide window).
    ///   - wide: A Mac window or regular-width iPad (full-window viewer) instead of a phone sheet.
    ///   - typeSize: Dynamic Type size.
    ///   - motion: Fades or Reduce Motion (system or in-app).
    ///   - failingTextReads: Text reads that answer 404 first.
    ///   - hold: Hold every path read until the test releases it.
    /// - Returns: The hosted sheet; its first load is running.
    static func host(
        display: PathDisplayMode = .text, viewMode: PathViewMode? = nil, wide: Bool = false,
        typeSize: DynamicTypeSize = .large, motion: Motion = .animated,
        failingTextReads: Int = 0, hold: Bool = false
    ) async throws -> Hosted {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/fixtures/path-demo.json")
        let transport = PathSwitchTransport(
            text: try Data(contentsOf: fixture), image: try switchPathPNG(), failingTextReads: failingTextReads
        )
        if hold { await transport.hold() }
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let song = try JSONDecoder().decode(Song.self, from: Data("""
        {"songId":"fixture-pulse","title":"Fixture Pulse",
         "artist":"Synthetic Quartet","pathArtifactGenerationId":"fixture-generation"}
        """.utf8))
        let suiteName = "fst-paths-switch-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let size = wide ? CGSize(width: 1280, height: 748) : CGSize(width: 390, height: 844)
        var signals = LayoutSignals(size: size, widthClass: wide ? .regular : .compact)
        signals.usesSidebarShell = wide
        let host = nativeHostedView(
            AnyView(
                SongPathsSheet(
                    song: song, session: session, instruments: [.lead, .drums],
                    firstInstrument: .lead, defaultDisplay: display,
                    warnAboutKaraoke: false, viewMode: viewMode
                )
                .environment(\.deviceLayout, DeviceLayout.resolve(signals))
                .environment(\.festivalModalCoverage, wide ? .fullScreen : .sheet)
                .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
                .environment(\.dynamicTypeSize, typeSize)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
                .tint(BrandTokens.accentBlue)
            ),
            size: size
        )
        return Hosted(
            host: host, window: nativeHostedWindow(host, size: size), transport: transport,
            storage: storage, suiteName: suiteName
        )
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    static func spinners(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.role == "AXBusyIndicator" }
    }

    /// Activation cards, the table and the error: anything a spinner must replace.
    static func pathContent(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter {
            $0.identifier.hasPrefix("fst.paths.activation.") || $0.identifier.hasPrefix("fst.paths.text.")
                || $0.identifier == "fst.paths.image" || $0.identifier == "fst.paths.error"
                || $0.identifier.hasPrefix("fst.service-status.")
        }
    }

    /// The elements VoiceOver lands on, by identifier or (for the spinners) name, in order.
    static func order(_ nodes: [MacAXNode]) -> [String] {
        nodes.filter { $0.isElement && ($0.role == "AXBusyIndicator" || $0.identifier.hasPrefix("fst.")) }
            .map { $0.role == "AXBusyIndicator" ? $0.label : $0.identifier }
    }

    /// Expect the selectors to stay named, enabled pop-up buttons showing the selection,
    /// whatever the content area shows (load-transition R4).
    static func expectSelectorsUsable(_ hosted: Hosted, _ context: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let nodes = hosted.reachable()
        for (id, value) in selectors {
            let node = nodes.first { $0.identifier == id }
            #expect(node?.role == "AXPopUpButton" && node?.spokenName == value,
                    "\(context): \(id) reads \(value):\n\(dump(nodes))", sourceLocation: sourceLocation)
            let element = nativeHostedAccessibilityElement(id, in: hosted.host)
            let enabled = element.flatMap {
                $0.responds(to: NSSelectorFromString("isAccessibilityEnabled"))
                    ? $0.value(forKey: "isAccessibilityEnabled") as? Bool : nil
            }
            #expect(enabled == true, "\(context): \(id) stays enabled", sourceLocation: sourceLocation)
        }
        // Each selector's visible name ("Instrument", "Difficulty", "View") reads just before it.
        let names = nodes.filter { ["Instrument", "Difficulty", "View"].contains($0.spokenName) && $0.role == "AXStaticText" }
        #expect(names.map(\.spokenName) == ["Instrument", "Difficulty", "View"], "\(context)\n\(dump(nodes))",
                sourceLocation: sourceLocation)
    }

    /// Wait until the table's cards are on screen and the spinner has left.
    static func settleOnCards(_ hosted: Hosted, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30), sourceLocation: sourceLocation) {
            let nodes = hosted.reachable()
            return nodes.contains { $0.identifier == "fst.paths.activation.2" } && spinners(nodes).isEmpty
        }
    }

    // MARK: First load

    /// While the table loads, its pane is one busy indicator named "Loading text path"
    /// (no card, table or error behind it, nothing unnamed) read before the selectors,
    /// which stay named, enabled and on their selection. After the reveal the spinner
    /// leaves the tree and the activation cards read top to bottom, each one element with
    /// a spoken value, before the selectors. Same at the largest accessibility text size,
    /// where the cards still fit the sheet's width.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func firstLoadReadsOneNamedSpinnerThenTheCardsInOrder(_ typeSize: DynamicTypeSize) async throws {
        let hosted = try await Self.host(typeSize: typeSize, hold: true)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            !Self.spinners(hosted.reachable()).isEmpty
        }

        let loading = hosted.reachable()
        let spinner = try #require(Self.spinners(loading).first, Comment(rawValue: Self.dump(loading)))
        #expect(Self.spinners(loading).count == 1, "one spinner:\n\(Self.dump(loading))")
        #expect(spinner.label == "Loading text path", "\(spinner)")
        #expect(Self.pathContent(loading).isEmpty, "nothing behind the spinner:\n\(Self.dump(loading))")
        #expect(ReloadGateAccessibilityTests.leaves(loading).allSatisfy { !$0.spokenName.isEmpty },
                "nothing unnamed:\n\(Self.dump(loading))")
        #expect(Self.order(loading) == ["Loading text path"] + Self.selectorIDs, "\(Self.dump(loading))")
        Self.expectSelectorsUsable(hosted, "\(typeSize) loading")

        await hosted.transport.release()
        try await Self.settleOnCards(hosted)
        let loaded = hosted.reachable()
        #expect(Self.order(loaded) == ["fst.paths.text.Solo_Guitar.expert", "fst.paths.activation.1", "fst.paths.activation.2"]
            + Self.selectorIDs, "cards, then selectors:\n\(Self.dump(loaded))")
        let cards = loaded.filter { $0.identifier.hasPrefix("fst.paths.activation.") }
        #expect(cards.map(\.label) == ["Activation 1", "Activation 2"], "\(cards)")
        // SwiftUI on macOS speaks a string `accessibilityValue` as the AX value description.
        let values = cards.map { card in
            nativeHostedAccessibilityElement(card.identifier, in: hosted.host)
                .map { nativeHostedAccessibilityString($0, "accessibilityValueDescription") } ?? ""
        }
        #expect(values.allSatisfy { $0.contains("beat ") && $0.contains("time ") }, "each card speaks its details: \(values)")
        let frames = cards.compactMap { hosted.frame($0) }
        #expect(frames.count == 2 && frames[0].maxY <= frames[1].minY + 0.5, "top to bottom: \(frames)")
        #expect(frames.allSatisfy { $0.minX >= -0.5 && $0.maxX <= hosted.host.bounds.width + 0.5 },
                "cards fit the sheet's width at \(typeSize): \(frames)")
        Self.expectSelectorsUsable(hosted, "\(typeSize) loaded")
    }

    // MARK: Switch

    /// A switch (here Retry on a failed chart, pressed the way VoiceOver, Voice Control or
    /// Full Keyboard Access press it) removes the error from the tree at once and puts one
    /// named spinner in its place, never both; the selectors stay usable throughout. The
    /// new cards appear only after the spinner's minimum (500 ms for the table), plus the
    /// two 300 ms fades with motion. Under system or in-app Reduce Motion the swap has no
    /// fades (`switchTimingHonorsSystemAndInAppReduceMotion`) but keeps the minimum, so
    /// the spinner never blinks. Durations are lower bounds, so a slow runner can't fail them.
    @Test(arguments: Motion.allCases)
    func retrySwapsTheErrorForOneNamedSpinnerThenTheCards(_ motion: Motion) async throws {
        let hosted = try await Self.host(motion: motion, failingTextReads: 1)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            hosted.reachable().contains { $0.identifier == "fst.service-status.retry" }
        }
        let failed = hosted.reachable()
        #expect(failed.contains { $0.role == "AXHeading" && $0.spokenName == "Path unavailable" }, "\(Self.dump(failed))")
        let retryNode = try #require(failed.first { $0.identifier == "fst.service-status.retry" })
        #expect(retryNode.role == "AXButton" && retryNode.spokenName == "Retry", "\(retryNode)")
        #expect(Self.spinners(failed).isEmpty, "\(Self.dump(failed))")

        await hosted.transport.hold()
        let retry = try #require(nativeHostedAccessibilityElement("fst.service-status.retry", in: hosted.host))
        let press = NSSelectorFromString("accessibilityPerformPress")
        #expect(retry.responds(to: press))
        let clock = ContinuousClock()
        let start = clock.now
        _ = retry.perform(press)

        // Every state on the way to the spinner: the error is never read again, and never
        // beside the spinner.
        var states: [[MacAXNode]] = []
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            let nodes = hosted.reachable()
            states.append(nodes)
            return !Self.spinners(nodes).isEmpty
        }
        #expect(states.allSatisfy { Self.pathContent($0).isEmpty },
                "the error leaves at once:\n\(states.map(Self.dump).joined(separator: "\n--\n"))")
        let switching = hosted.reachable()
        #expect(Self.spinners(switching).map(\.label) == ["Loading text path"], "\(Self.dump(switching))")
        #expect(Self.order(switching) == ["Loading text path"] + Self.selectorIDs, "\(Self.dump(switching))")
        Self.expectSelectorsUsable(hosted, "\(motion) switching")

        await hosted.transport.release()
        try await Self.settleOnCards(hosted)
        let elapsed = clock.now - start
        let timing = PathSwitchTransition.timing(for: .text, reduceMotion: motion != .animated)
        // With motion the old content fades out, then the spinner, before the cards fade in.
        let fades = motion == .animated ? timing.fade * 2 : .zero
        #expect(elapsed >= timing.minimumSpinner + fades, "revealed after \(elapsed)")
        let loaded = hosted.reachable()
        #expect(Self.pathContent(loaded).allSatisfy { !$0.identifier.hasPrefix("fst.service-status.") },
                "no stale error beside the cards:\n\(Self.dump(loaded))")
        #expect(Self.order(loaded) == ["fst.paths.text.Solo_Guitar.expert", "fst.paths.activation.1", "fst.paths.activation.2"]
            + Self.selectorIDs, "\(Self.dump(loaded))")
    }

    // MARK: Side by Side

    /// Side by Side (Mac window, iPad, unfolded iPhone Duo) loads both forms with their
    /// own spinners: "Loading image path" reads before "Loading text path", matching the
    /// image on the leading half and the table on the trailing half. After the reveal the
    /// image, then the cards, then the selectors read in the same visual order.
    @Test func sideBySideReadsEachPaneSpinnerThenItsContentInVisualOrder() async throws {
        let hosted = try await Self.host(viewMode: .sideBySide, wide: true, hold: true)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            Self.spinners(hosted.reachable()).count == 2
        }
        let loading = hosted.reachable()
        let spinners = Self.spinners(loading)
        #expect(spinners.map(\.label) == ["Loading image path", "Loading text path"], "\(Self.dump(loading))")
        #expect(Self.pathContent(loading).isEmpty, "\(Self.dump(loading))")
        let imageSpinner = try #require(hosted.frame(spinners[0]))
        let textSpinner = try #require(hosted.frame(spinners[1]))
        #expect(imageSpinner.maxX <= textSpinner.minX, "image pane leads: \(imageSpinner) vs \(textSpinner)")
        #expect(Self.order(loading) == ["Loading image path", "Loading text path"] + Self.selectorIDs,
                "\(Self.dump(loading))")

        await hosted.transport.release()
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            let nodes = hosted.reachable()
            return nodes.contains { $0.identifier == "fst.paths.activation.2" }
                && nodes.contains { $0.identifier == "fst.paths.image" } && Self.spinners(nodes).isEmpty
        }
        let loaded = hosted.reachable()
        #expect(Self.order(loaded) == [
            "fst.paths.image-viewport", "fst.paths.image",
            "fst.paths.text.Solo_Guitar.expert", "fst.paths.activation.1", "fst.paths.activation.2",
        ] + Self.selectorIDs, "\(Self.dump(loaded))")
        let image = try #require(loaded.first { $0.identifier == "fst.paths.image" })
        #expect(image.label == "Lead Expert CHOpt path", "\(image)")
    }

    // MARK: Announcements and timing

    /// What VoiceOver hears on a switch names the chart and the form, then the result,
    /// and only after a switch: never on the first load, and in Side by Side only the
    /// table speaks, so one switch is announced once.
    @Test func switchAnnouncementsNameTheChartAndFollowOnlyASwitch() {
        #expect(SongPathsSheet.loadingAnnouncement(instrument: .lead, difficulty: .hard, display: .image)
            == "Loading Lead Hard image path")
        #expect(SongPathsSheet.loadingAnnouncement(instrument: .bass, difficulty: .expert, display: .text)
            == "Loading Bass Expert text path")
        #expect(SongPathsSheet.loadedAnnouncement(instrument: .lead, difficulty: .hard, activations: nil)
            == "Lead Hard path image")
        #expect(SongPathsSheet.loadedAnnouncement(instrument: .lead, difficulty: .hard, activations: 1)
            == "Lead Hard path, 1 activation")
        #expect(SongPathsSheet.loadedAnnouncement(instrument: .lead, difficulty: .hard, activations: 2)
            == "Lead Hard path, 2 activations")

        for mode in PathViewMode.allCases {
            for display in PathDisplayMode.allCases {
                #expect(!SongPathsSheet.announcesSwitch(of: display, in: mode, afterSwitch: false),
                        "first load of \(display) in \(mode) is silent")
            }
        }
        #expect(SongPathsSheet.announcesSwitch(of: .image, in: .image, afterSwitch: true))
        #expect(SongPathsSheet.announcesSwitch(of: .text, in: .text, afterSwitch: true))
        #expect(SongPathsSheet.announcesSwitch(of: .text, in: .sideBySide, afterSwitch: true))
        #expect(!SongPathsSheet.announcesSwitch(of: .image, in: .sideBySide, afterSwitch: true))
    }

    /// The in-app Reduce Motion setting stops the switch fades like the system setting
    /// (it was ignored until #430); either keeps the spinner's minimum hold.
    @Test func switchTimingHonorsSystemAndInAppReduceMotion() {
        for display in PathDisplayMode.allCases {
            let minimum = PathSwitchTransition.minimumSpinner(for: display)
            let animated = SongPathsSheet.switchTiming(for: display, systemReduceMotion: false, appReduceMotion: false)
            #expect(animated == .init(fade: PathSwitchTransition.fade, minimumSpinner: minimum))
            for (system, app) in [(true, false), (false, true), (true, true)] {
                #expect(SongPathsSheet.switchTiming(for: display, systemReduceMotion: system, appReduceMotion: app)
                    == .init(fade: .zero, minimumSpinner: minimum), "system \(system), app \(app)")
            }
        }
    }
}
#endif
