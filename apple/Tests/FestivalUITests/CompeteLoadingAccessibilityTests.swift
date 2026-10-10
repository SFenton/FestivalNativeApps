#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Compete loading accessibility (issue #35, backfilled by #407)

// #35 gave Compete a system spinner while it loads; #354 then made it one page spinner
// behind the canonical `FestivalReloadGate` ("Loading Compete", `fst.compete.loading`).
// These hosted checks (macOS host, `apple-ci`) pin what that state exposes to VoiceOver,
// Voice Control and Dynamic Type on iPhone, iPad, iPhone Duo and Mac, since `CompeteScreen`
// is the same SwiftUI on each: while any leaderboard read runs, the page is one named
// busy indicator, with no section heading, instrument header, card, per-card spinner or
// unnamed element behind it; once every read settles the spinner leaves the tree and the
// sections read in visual order (Leaderboards heading, each instrument heading, its rows
// and its 44 pt View Full Leaderboard button, then the Rivals heading); when every
// leaderboard fails, the spinner gives way to a heading and a named 44 pt Retry. Reduce
// Motion (system or in-app) and the largest accessibility text size change none of it.
// macOS keeps the font size, so the AX5 cases pin the tree only; the iPhone XCUITest
// `CompeteAccessibilityJourneyTests` proves real AX5 glyph growth, whole text and reach.
// The generic gate sequence is pinned by `ReloadGateAccessibilityTests`.

// MARK: - Fixture

/// Holds Compete's leaderboard reads until released, or fails them, forwarding every
/// other read to the loopback fixture (`tools/mock_service.py`).
actor HeldCompeteRankingsTransport: HTTPTransport {
    /// What a leaderboard read does.
    enum Mode: Sendable {
        /// Wait until the mode changes.
        case hold
        /// Answer 503 at once.
        case fail
        /// Forward to the fixture.
        case pass
    }

    private let inner = URLSessionHTTPTransport()
    private var mode: Mode

    /// - Parameter mode: What leaderboard reads do until ``set(_:)`` changes it.
    init(_ mode: Mode) {
        self.mode = mode
    }

    /// Change what held and later leaderboard reads do.
    func set(_ mode: Mode) {
        self.mode = mode
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.url?.path.hasPrefix("/api/rankings/") == true else { return try await inner.send(request) }
        while mode == .hold { try await Task.sleep(for: .milliseconds(20)) }
        if mode == .fail { return HTTPResult(status: 503, data: Data(#"{"error":"unavailable"}"#.utf8)) }
        return try await inner.send(request)
    }
}

/// Accessibility of Compete's loading state (#35) and what replaces it.
///
/// HIG Progress indicators: progress indicators appear "only while one is ongoing";
/// HIG VoiceOver: "be sure to keep labels current as interface and content change";
/// HIG Accessibility: 44×44 pt default control size on iOS/iPadOS, and "When Reduce
/// Motion is on, reduce automatic and repetitive animation".
@MainActor
@Suite(.serialized)
struct CompeteLoadingAccessibilityTests {
    /// The page spinner's spoken name and identifier.
    static let spinnerLabel = "Loading Compete"
    static let spinnerID = "fst.compete.loading"
    /// The instruments the fixture shows, in Settings order.
    static let instruments = ["Lead", "Bass"]
    static let visibleKeys: Set<String> = ["fst.settings.showLead", "fst.settings.showBass"]
    static let allInstrumentKeys = [
        "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
        "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
        "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
    ]
    /// HIG Accessibility: iOS/iPadOS default control size.
    static let minimumTarget: CGFloat = 44

    /// How the page moves.
    enum Motion: String, CaseIterable, CustomTestStringConvertible {
        /// Fades off (the hosted default): every step is instant.
        case instant
        /// Fades on, system Reduce Motion.
        case systemReduceMotion
        /// Fades on, the app's own Reduce Motion setting.
        case appReduceMotion

        var testDescription: String { rawValue }
    }

    /// One hosted Compete page.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let transport: HeldCompeteRankingsTransport
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// The current tree in VoiceOver's navigation order, after one layout pass.
        func tree() -> [MacAXNode] {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            return macAccessibilityTree(host, navigationOrder: true)
        }

        /// The elements VoiceOver reaches through `accessibilityChildren` alone, with
        /// their frames in the host's top-left points. Unlike ``tree()``, it skips the
        /// unexposed `NSProgressIndicator` backing a SwiftUI `ProgressView`.
        func reachable() -> [MacAXNode] {
            framedReachable().map(\.node)
        }

        /// ``reachable()`` with each element's frame.
        func framedReachable() -> [(node: MacAXNode, frame: CGRect?)] {
            host.layoutSubtreeIfNeeded()
            var found: [(node: MacAXNode, frame: CGRect?)] = []
            var seen = Set<ObjectIdentifier>()
            func walk(_ node: Any, depth: Int) {
                guard depth < 90, let object = node as? NSObject,
                      seen.insert(ObjectIdentifier(object)).inserted else { return }
                func read(_ key: String) -> String { nativeHostedAccessibilityString(object, key) }
                let isElement = object.responds(to: NSSelectorFromString("isAccessibilityElement"))
                    && (object.value(forKey: "isAccessibilityElement") as? Bool) == true
                if isElement {
                    found.append((MacAXNode(
                        depth: depth, role: read("accessibilityRole"), subrole: read("accessibilitySubrole"),
                        label: read("accessibilityLabel"), title: read("accessibilityTitle"),
                        value: read("accessibilityValue"), identifier: read("accessibilityIdentifier"),
                        selected: false, help: "", isElement: true
                    ), nativeHostedAccessibilityFrame(of: object, in: host)))
                }
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [Any] : nil
                for child in children ?? [] { walk(child, depth: depth + 1) }
            }
            walk(host, depth: 0)
            return found
        }
    }

    /// Host Compete for `fixture-riv` with Lead and Bass on a phone-width window.
    ///
    /// - Parameters:
    ///   - mode: What the leaderboard reads do at first.
    ///   - typeSize: Dynamic Type size for the page.
    ///   - motion: Fade and Reduce Motion settings.
    /// - Returns: The host; the first load is still running.
    static func host(
        _ mode: HeldCompeteRankingsTransport.Mode = .hold, typeSize: DynamicTypeSize = .large,
        motion: Motion = .instant
    ) async throws -> Hosted {
        let transport = HeldCompeteRankingsTransport(mode)
        let baseURL = try await RivalsMockService.shared.baseURL()
        let client = try FestivalAPI(baseURL: baseURL, transport: transport)
        let suiteName = "fst.tests.compete-a11y.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        let identity: [String: String] = ["accountId": "fixture-riv", "displayName": "Fixture Viewer"]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        for key in allInstrumentKeys { storage.set(visibleKeys.contains(key), forKey: key) }
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        let size = CGSize(width: 402, height: 1400)
        let host = nativeHostedView(
            AnyView(
                NavigationStack { CompeteScreen(session: session) }
                    .environment(\.festivalFadeInEnabled, motion != .instant)
                    .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
                    .environment(\.dynamicTypeSize, typeSize)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
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

    /// The page's own elements VoiceOver lands on, in its reading order: no grouping
    /// containers and no system scroller parts.
    static func content(_ framed: [(node: MacAXNode, frame: CGRect?)]) -> [(node: MacAXNode, frame: CGRect?)] {
        var scrollerDepth: Int?
        var result: [(node: MacAXNode, frame: CGRect?)] = []
        for item in framed {
            if let depth = scrollerDepth, item.node.depth > depth { continue }
            scrollerDepth = nil
            if item.node.role == "AXScrollBar" {
                scrollerDepth = item.node.depth
            } else if !["AXGroup", "AXScrollArea", "AXOpaqueProviderGroup"].contains(item.node.role) {
                result.append(item)
            }
        }
        return result
    }

    /// ``content(_:)`` without frames.
    static func content(_ hosted: Hosted) -> [MacAXNode] {
        content(hosted.framedReachable()).map(\.node)
    }

    static func busyIndicators(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.isElement && $0.role == "AXBusyIndicator" }
    }

    /// Wait until the page spinner is up, then long enough for the unheld rivals reads
    /// to settle behind it.
    static func settleOnSpinner(_ hosted: Hosted, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30), sourceLocation: sourceLocation) {
            macAccessibilityTree(hosted.host).contains { $0.identifier == spinnerID }
        }
        try await Task.sleep(for: .milliseconds(500))
    }

    /// While a read runs, VoiceOver meets exactly one element: the system busy
    /// indicator named "Loading Compete", lying on the page. No heading, card, row,
    /// per-card spinner (#35's first form) or unnamed element is reachable behind it.
    static func expectOneNamedSpinner(
        _ hosted: Hosted, _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let reachable = hosted.reachable()
        let elements = content(hosted)
        let spinner = try #require(elements.only, "\(context): one element while loading:\n\(dump(reachable))",
                                   sourceLocation: sourceLocation)
        #expect(spinner.role == "AXBusyIndicator", "\(context): \(spinner)", sourceLocation: sourceLocation)
        #expect(spinner.label == spinnerLabel, "\(context): \(spinner)", sourceLocation: sourceLocation)
        #expect(spinner.identifier == spinnerID, "\(context): \(spinner)", sourceLocation: sourceLocation)
        let frame = try #require(nativeHostedAccessibilityFrame(spinnerID, in: hosted.host),
                                 "\(context): the spinner has a frame", sourceLocation: sourceLocation)
        #expect(!frame.isEmpty && hosted.host.bounds.contains(frame),
                "\(context): the spinner lies on the page: \(frame)", sourceLocation: sourceLocation)
        #expect(macAccessibilityFindings(hosted.tree()).isEmpty, "\(context)", sourceLocation: sourceLocation)
    }

    /// Expect `id`'s accessibility frame to be at least a 44×44 pt target lying across
    /// the page's width.
    static func expectTarget(
        _ hosted: Hosted, _ id: String, _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let frame = nativeHostedAccessibilityFrame(id, in: hosted.host) else {
            Issue.record("\(context): \(id) has no accessibility frame", sourceLocation: sourceLocation)
            return
        }
        let minimum = minimumTarget - 0.5
        #expect(frame.width >= minimum && frame.height >= minimum,
                "\(context): \(id) is a 44×44 pt target: \(frame)", sourceLocation: sourceLocation)
        #expect(frame.minX >= -0.5 && frame.maxX <= hosted.host.bounds.width + 0.5,
                "\(context): \(id) lies across the page: \(frame)", sourceLocation: sourceLocation)
    }

    // MARK: First load

    /// The first load reads as one named spinner, at the standard and the largest
    /// accessibility text size and with Reduce Motion from the system or the app. Once
    /// every read settles the spinner leaves the tree, and the page reads in visual
    /// order: the Leaderboards heading; each instrument's heading, its rows top to bottom
    /// and its View Full Leaderboard button (a named 44 pt button); then the Rivals
    /// heading and its instrument headings.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5], Motion.allCases)
    func firstLoadReadsOneNamedSpinnerThenSectionsInOrder(_ typeSize: DynamicTypeSize, _ motion: Motion) async throws {
        let context = "\(typeSize), \(motion)"
        let hosted = try await Self.host(typeSize: typeSize, motion: motion)
        defer { hosted.close() }
        try await Self.settleOnSpinner(hosted)
        try Self.expectOneNamedSpinner(hosted, "\(context), loading")

        await hosted.transport.set(.pass)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            let tree = macAccessibilityTree(hosted.host)
            return !tree.contains { $0.identifier == Self.spinnerID }
                && tree.contains { $0.spokenName == "View Full Leaderboard, Bass" }
                && tree.contains { $0.spokenName == "Bass Rivals" }
        }
        let reachable = hosted.reachable()
        let framed = Self.content(hosted.framedReachable())
        let loaded = framed.map(\.node)
        #expect(Self.busyIndicators(reachable).isEmpty, "\(context): the spinner leaves:\n\(Self.dump(loaded))")
        #expect(!loaded.contains { $0.spokenName.hasPrefix("Loading") }, "\(context):\n\(Self.dump(loaded))")
        #expect(loaded.filter { $0.role == "AXHeading" }.map(\.spokenName)
            == ["Leaderboards", "Lead", "Bass", "Rivals", "Lead Rivals", "Bass Rivals"],
            "\(context): headings in page order:\n\(Self.dump(loaded))")
        for (index, instrument) in Self.instruments.enumerated() {
            let heading = try #require(loaded.firstIndex { $0.role == "AXHeading" && $0.spokenName == instrument })
            let button = try #require(loaded.firstIndex { $0.spokenName == "View Full Leaderboard, \(instrument)" },
                                      "\(context): \(instrument)'s View Full Leaderboard:\n\(Self.dump(loaded))")
            let next = index + 1 < Self.instruments.count ? Self.instruments[index + 1] : "Rivals"
            let end = try #require(loaded.firstIndex { $0.role == "AXHeading" && $0.spokenName == next })
            #expect(loaded[button].role == "AXButton", "\(context): \(loaded[button])")
            let rows = loaded[(heading + 1)..<button]
            #expect(!rows.isEmpty && rows.allSatisfy { $0.identifier.hasPrefix("fst.rankings.row.") },
                    "\(context): \(instrument)'s heading, its rows, then its button:\n\(Self.dump(loaded))")
            #expect(button + 1 == end, "\(context): \(instrument)'s button ends its card:\n\(Self.dump(loaded))")
            let tops = framed[(heading + 1)..<button].compactMap(\.frame?.minY)
            #expect(tops.count == rows.count && tops == tops.sorted(),
                    "\(context): \(instrument)'s rows read top to bottom: \(tops)")
            let card = "fst.compete.leaderboard-card.\(index == 0 ? "Solo_Guitar" : "Solo_Bass").view-all"
            Self.expectTarget(hosted, card, context)
        }
        #expect(loaded.allSatisfy { !$0.spokenName.isEmpty }, "\(context): nothing unnamed:\n\(Self.dump(loaded))")
        #expect(macAccessibilityFindings(hosted.tree()).isEmpty, "\(context)")
    }

    // MARK: Page error and retry

    /// When every leaderboard fails, the spinner gives way to the page's error: a
    /// heading, then a named 44 pt Retry button, and no busy indicator. Pressing Retry
    /// brings back the one named spinner, never a spinner per card, until the reads
    /// settle again; then the sections read as on a first load.
    @Test func everyLeaderboardFailingReplacesTheSpinnerWithAHeadingAndRetry() async throws {
        let hosted = try await Self.host(.fail)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            macAccessibilityTree(hosted.host).contains { $0.identifier == "fst.service-status.retry" }
        }
        let reachable = hosted.reachable()
        let failed = Self.content(hosted)
        #expect(Self.busyIndicators(reachable).isEmpty, "no spinner beside the error:\n\(Self.dump(failed))")
        let heading = try #require(failed.firstIndex { $0.identifier == "fst.service-status.title" },
                                   "\(Self.dump(failed))")
        #expect(failed[heading].role == "AXHeading" && failed[heading].spokenName == "Compete unavailable",
                "\(failed[heading])")
        let retry = try #require(failed.firstIndex { $0.identifier == "fst.service-status.retry" })
        #expect(heading < retry, "the heading reads before Retry:\n\(Self.dump(failed))")
        #expect(failed[retry].role == "AXButton" && failed[retry].spokenName.hasPrefix("Retry"), "\(failed[retry])")
        #expect(!failed.contains { $0.role == "AXHeading" && ["Leaderboards", "Rivals"].contains($0.spokenName) },
                "no section behind the page error:\n\(Self.dump(failed))")
        Self.expectTarget(hosted, "fst.service-status.retry", "page error")
        #expect(macAccessibilityFindings(hosted.tree()).isEmpty)

        await hosted.transport.set(.hold)
        let button = try #require(nativeHostedAccessibilityElement("fst.service-status.retry", in: hosted.host))
        let press = NSSelectorFromString("accessibilityPerformPress")
        #expect(button.responds(to: press))
        _ = button.perform(press)
        try await Self.settleOnSpinner(hosted)
        try Self.expectOneNamedSpinner(hosted, "retrying")

        await hosted.transport.set(.pass)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            let tree = macAccessibilityTree(hosted.host)
            return !tree.contains { $0.identifier == Self.spinnerID }
                && tree.contains { $0.spokenName == "View Full Leaderboard, Bass" }
        }
        let reloaded = Self.content(hosted)
        #expect(reloaded.filter { $0.role == "AXHeading" }.prefix(3).map(\.spokenName) == ["Leaderboards", "Lead", "Bass"],
                "\(Self.dump(reloaded))")
        #expect(!reloaded.contains { $0.identifier.hasPrefix("fst.service-status.") }, "\(Self.dump(reloaded))")
    }
}

private extension Array {
    /// The single element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
#endif
