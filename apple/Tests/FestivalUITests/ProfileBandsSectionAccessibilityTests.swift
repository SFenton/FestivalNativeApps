#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Profile bands section (issue #312, backfilled by #463)

// #312 put the player's bands inline on the profile (`PlayerBandsPreviewSection`): a
// "{name}'s Bands" title with its View All link, then Duos, Trios and Quads, each a card
// of band rows or a "No Bands Yet" card, behind a named spinner while the three reads run
// and an inline error with Retry when they fail. `ProfileBandsCardAccessibilityTests`
// (#596) pins the loaded group cards (rows, the per-group View All Bands, their order and
// targets); these hosted checks (macOS host, `apple-ci`) pin the rest of the section on
// iPhone, iPad, iPhone Duo and Mac, which share the SwiftUI: the title is a heading read
// first, then its View All link (one named 44×44 pt button that opens the full list by
// AXPress, the action VoiceOver, Voice Control, Switch Control and Full Keyboard Access
// use); while loading only the named spinner sits under them; a failure reads its message
// and a named Retry that keeps its own identifier and brings the spinner back (the iPhone
// journey pins Retry's 44×44 pt iOS target); an empty group reads its heading and
// then one "No Bands Yet" element, with no View All Bands. The largest accessibility size
// changes none of it. macOS keeps the font size, so the iPhone XCUITest
// `ProfileBandsAccessibilityJourneyTests` proves real AX5 growth, whole text and reach.

// MARK: - Fixture

/// Holds the profile's player-bands reads until released, or fails them, forwarding every
/// other read to the loopback fixture (`tools/mock_service.py`).
actor HeldPlayerBandsTransport: HTTPTransport {
    /// What a player-bands read does.
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

    /// - Parameter mode: What player-bands reads do until ``set(_:)`` changes it.
    init(_ mode: Mode) {
        self.mode = mode
    }

    /// Change what held and later player-bands reads do.
    func set(_ mode: Mode) {
        self.mode = mode
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        guard path.hasPrefix("/api/player/"), path.hasSuffix("/bands") else { return try await inner.send(request) }
        while mode == .hold { try await Task.sleep(for: .milliseconds(20)) }
        if mode == .fail { return HTTPResult(status: 503, data: Data(#"{"error":"unavailable"}"#.utf8)) }
        return try await inner.send(request)
    }
}

/// Accessibility of the profile's inline bands section (#312) outside its loaded cards.
///
/// HIG Accessibility: 44×44 pt default control size on iOS/iPadOS; HIG VoiceOver: "be
/// sure to keep labels current as interface and content change"; HIG Progress
/// indicators: show one "only while one is ongoing"; HIG Writing: show errors "as close
/// to the problem as possible".
@MainActor
@Suite(.serialized)
struct ProfileBandsSectionAccessibilityTests {
    // MARK: - Constants

    static let groups: [PlayerBandGroup] = [.duos, .trios, .quads]
    static let linkID = "fst.player.bands-link"
    static let spinnerID = "fst.player.bands.loading"
    static let spinnerLabel = "Loading bands"
    static let retryID = "fst.service-status.retry"
    static let pushedPrefix = "fst.test.pushed."
    /// HIG Accessibility: iOS/iPadOS default control size.
    static let minimumTarget: CGFloat = 44
    /// The empty card's title and next step (web `player.noBandsTitle`/`noBandsSubtitle`).
    static let emptyTitle = "No Bands Yet"
    static let emptyHint = "Band lineups will appear here once this player posts band scores."

    /// The fixture players: 18 duos, 8 trios and 4 quads, or no bands at all.
    enum Player: String, CustomTestStringConvertible {
        case withBands = "fixture-player-1"
        case noBands = "fixture-player-2"

        var name: String { self == .withBands ? "Fixture Player 1" : "Fixture Player 2" }
        var title: String { "\(name)'s Bands" }
        var linkName: String { "View All \(title)" }
        var testDescription: String { rawValue }
    }

    // MARK: - Host

    /// One hosted bands section.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let transport: HeldPlayerBandsTransport

        func close() { window.orderOut(nil) }

        /// The section's own elements VoiceOver lands on, in its reading order, with
        /// frames: no grouping containers and no system scroller parts.
        func content() -> [(node: MacAXNode, frame: CGRect?)] {
            CompeteLoadingAccessibilityTests.content(nativeHostedReachableElements(host))
        }

        /// ``content()`` without frames.
        func nodes() -> [MacAXNode] { content().map(\.node) }
    }

    /// Host the section as the profile shows it, loading from the mock service through a
    /// held transport. Its routes push a marker view named after the route, so tests can
    /// see what activating a link opened.
    ///
    /// - Parameters:
    ///   - player: The fixture player.
    ///   - mode: What the player-bands reads do at first.
    ///   - typeSize: Dynamic Type size for the section.
    /// - Returns: The host; its first load may still be running.
    /// - Throws: An unreachable mock service.
    static func host(
        _ player: Player, _ mode: HeldPlayerBandsTransport.Mode, typeSize: DynamicTypeSize = .large
    ) async throws -> Hosted {
        let transport = HeldPlayerBandsTransport(mode)
        let baseURL = try await RivalsMockService.shared.baseURL()
        let client = try FestivalAPI(baseURL: baseURL, transport: transport)
        let session = FestivalSession(factory: { client })
        let size = CGSize(width: 402, height: 3000)
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    ScrollView {
                        PlayerBandsPreviewSection(
                            session: session, accountId: player.rawValue, displayName: player.name,
                            routeDisplayName: nil
                        )
                        .padding(16)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        Text("Opened")
                            .accessibilityIdentifier(pushedPrefix + pushedName(route))
                    }
                }
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        return Hosted(host: host, window: nativeHostedWindow(host, size: size), transport: transport)
    }

    /// The marker name for a pushed route: `player-bands` plus its starting group.
    static func pushedName(_ route: AppRoute) -> String {
        guard case let .playerBands(_, _, group) = route else { return "other" }
        return group == .all ? "player-bands" : "player-bands.\(group.rawValue)"
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    /// Wait until an element with `identifier` is in the tree.
    static func settle(on identifier: String, _ hosted: Hosted) async throws {
        try await nativeHostedSettle(hosted.host, timeout: .seconds(60)) {
            macAccessibilityTree(hosted.host).contains { $0.identifier == identifier }
        }
    }

    // MARK: - Expectations

    /// The section opens with its title, a heading, then its View All link: one named
    /// button of at least 44×44 pt on the title's line, inside the page. Returns the
    /// index after the link in `nodes`.
    @discardableResult
    static func expectHeader(
        _ hosted: Hosted, _ player: Player, _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Int {
        let framed = hosted.content()
        let nodes = framed.map(\.node)
        try #require(nodes.count >= 2, "\(context): title and link:\n\(dump(nodes))", sourceLocation: sourceLocation)
        #expect(nodes[0].role == "AXHeading" && nodes[0].spokenName == player.title,
                "\(context): the title is the first stop, a heading:\n\(dump(nodes))", sourceLocation: sourceLocation)
        let link = nodes[1]
        #expect(link.identifier == linkID && link.role == "AXButton" && link.spokenName == player.linkName,
                "\(context): View All follows the title, named for its list:\n\(dump(nodes))",
                sourceLocation: sourceLocation)
        #expect(nodes.filter { $0.spokenName == player.title }.count == 1,
                "\(context): the title reads once:\n\(dump(nodes))", sourceLocation: sourceLocation)
        let frame = try #require(nativeHostedAccessibilityFrame(linkID, in: hosted.host),
                                 "\(context): the link has a frame", sourceLocation: sourceLocation)
        #expect(frame.width >= minimumTarget - 0.5 && frame.height >= minimumTarget - 0.5,
                "\(context): View All is a 44×44 pt target: \(frame)", sourceLocation: sourceLocation)
        #expect(hosted.host.bounds.contains(frame), "\(context): View All lies on the page: \(frame)",
                sourceLocation: sourceLocation)
        if let title = framed[0].frame {
            #expect(frame.minY <= title.midY && title.midY <= frame.maxY,
                    "\(context): View All sits on the title's line: \(title) | \(frame)", sourceLocation: sourceLocation)
        }
        return 2
    }

    /// Nothing VoiceOver reaches is unnamed, and no tree finding.
    static func expectNamed(_ hosted: Hosted, _ context: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let nodes = hosted.nodes()
        #expect(nodes.allSatisfy { !$0.spokenName.trimmingCharacters(in: .whitespaces).isEmpty },
                "\(context): nothing unnamed:\n\(dump(nodes))", sourceLocation: sourceLocation)
        #expect(macAccessibilityFindings(macAccessibilityTree(hosted.host)).isEmpty, "\(context)",
                sourceLocation: sourceLocation)
    }

    /// While the reads run, the title and its link are followed only by the one named
    /// busy indicator: no group heading, card or empty message behind it.
    static func expectLoading(
        _ hosted: Hosted, _ player: Player, _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let after = try expectHeader(hosted, player, context, sourceLocation: sourceLocation)
        let nodes = hosted.nodes()
        let rest = Array(nodes.dropFirst(after))
        let spinner = try #require(rest.count == 1 ? rest.first : nil,
                                   "\(context): only the spinner under the title:\n\(dump(nodes))",
                                   sourceLocation: sourceLocation)
        #expect(spinner.role == "AXBusyIndicator" && spinner.label == spinnerLabel,
                "\(context): one named busy indicator: \(spinner)", sourceLocation: sourceLocation)
        #expect(nativeHostedAccessibilityFrame(spinnerID, in: hosted.host).map(hosted.host.bounds.contains) == true,
                "\(context): the spinner lies on the page", sourceLocation: sourceLocation)
        expectNamed(hosted, context, sourceLocation: sourceLocation)
    }

    /// Activate a control the way VoiceOver, Voice Control, Switch Control and Full
    /// Keyboard Access do: its AXPress action.
    static func press(_ identifier: String, in host: NSView) throws {
        let control = try #require(nativeHostedAccessibilityElement(identifier, in: host), "\(identifier) to press")
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(control.responds(to: press), "\(identifier) offers a press action")
        _ = control.perform(press)
    }

    // MARK: - Tests

    /// Loading: title, View All, then one spinner named "Loading bands"; once the reads
    /// settle the spinner leaves and the headings read in page order (title, Duos,
    /// Trios, Quads), each group's heading straight after the previous group's content.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func loadingReadsTitleLinkAndOneNamedSpinnerThenGroupsInOrder(_ typeSize: DynamicTypeSize) async throws {
        let context = "\(typeSize)"
        let hosted = try await Self.host(.withBands, .hold, typeSize: typeSize)
        defer { hosted.close() }
        try await Self.settle(on: Self.spinnerID, hosted)
        try Self.expectLoading(hosted, .withBands, "\(context), loading")

        await hosted.transport.set(.pass)
        try await Self.settle(on: "fst.player.bands.view-all.trios", hosted)
        let after = try Self.expectHeader(hosted, .withBands, "\(context), loaded")
        let nodes = hosted.nodes()
        #expect(!nodes.contains { $0.role == "AXBusyIndicator" || $0.spokenName == Self.spinnerLabel },
                "\(context): the spinner leaves:\n\(Self.dump(nodes))")
        #expect(nodes.filter { $0.role == "AXHeading" }.map(\.spokenName)
            == [Player.withBands.title] + Self.groups.map(\.label),
            "\(context): headings in page order:\n\(Self.dump(nodes))")
        #expect(nodes[after].identifier == "fst.player.bands.group.duos",
                "\(context): Duos follows View All:\n\(Self.dump(nodes))")
        Self.expectNamed(hosted, context)
    }

    /// Failure: title and View All stay first and usable, then the inline error's message
    /// (static text: the section title is its heading, `ServiceStatusInline`) and a named
    /// Retry that keeps its own identifier, with no spinner. Pressing Retry brings
    /// the named spinner back until the reads settle, then the groups.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func failureReadsMessageThenRetryWhichBringsBackTheSpinner(_ typeSize: DynamicTypeSize) async throws {
        let context = "\(typeSize)"
        let hosted = try await Self.host(.withBands, .fail, typeSize: typeSize)
        defer { hosted.close() }
        try await Self.settle(on: "fst.player.bands.error", hosted)
        let after = try Self.expectHeader(hosted, .withBands, "\(context), failed")
        let nodes = hosted.nodes()
        #expect(!nodes.contains { $0.role == "AXBusyIndicator" }, "\(context): no spinner beside the error")
        let rest = Array(nodes.dropFirst(after))
        // The message, its automatic-retry countdown when one runs, then Retry.
        #expect(rest.count >= 2 && rest.first?.role == "AXStaticText" && rest.last?.role == "AXButton"
                    && rest.dropFirst().dropLast().allSatisfy { $0.spokenName.hasPrefix("Trying again") },
                "\(context): the message, then Retry:\n\(Self.dump(nodes))")
        #expect(rest.first?.spokenName == "Bands unavailable", "\(context): the message names what failed")
        let retry = try #require(rest.last)
        #expect(retry.identifier == Self.retryID && retry.spokenName.hasPrefix("Retry"),
                "\(context): Retry keeps its own name and identifier: \(retry)")
        #expect(nativeHostedAccessibilityFrame("fst.player.bands.error", in: hosted.host) != nil,
                "\(context): the error card keeps its identifier")
        // macOS keeps the system push button (HIG macOS minimum 20×20 pt); the iPhone
        // journey `ProfileBandsAccessibilityJourneyTests` pins its iOS 44×44 pt target.
        let frame = try #require(nativeHostedAccessibilityFrame(Self.retryID, in: hosted.host))
        #expect(frame.width >= 20 && frame.height >= 20, "\(context): Retry is a macOS-sized target: \(frame)")
        Self.expectNamed(hosted, "\(context), failed")

        await hosted.transport.set(.hold)
        try Self.press(Self.retryID, in: hosted.host)
        try await Self.settle(on: Self.spinnerID, hosted)
        try Self.expectLoading(hosted, .withBands, "\(context), retrying")

        await hosted.transport.set(.pass)
        try await Self.settle(on: "fst.player.bands.view-all.trios", hosted)
        #expect(!hosted.nodes().contains { $0.identifier == Self.retryID }, "\(context): Retry leaves with the error")
    }

    /// A player with no bands: after the title and View All, each group reads its
    /// heading and then one static "No Bands Yet" element (title, then its next step),
    /// at least 44 pt tall, with no View All Bands and no row.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func emptyGroupsReadHeadingThenOneNoBandsYetElement(_ typeSize: DynamicTypeSize) async throws {
        let context = "\(typeSize)"
        let hosted = try await Self.host(.noBands, .pass, typeSize: typeSize)
        defer { hosted.close() }
        try await Self.settle(on: "fst.player.bands.empty.quads", hosted)
        let after = try Self.expectHeader(hosted, .noBands, context)
        let nodes = hosted.nodes()
        let expected = Self.groups.flatMap { ["fst.player.bands.group.\($0.rawValue)", "fst.player.bands.empty.\($0.rawValue)"] }
        #expect(nodes.dropFirst(after).map(\.identifier) == expected,
                "\(context): heading, then its empty card, group by group:\n\(Self.dump(nodes))")
        for group in Self.groups {
            let empty = try #require(nodes.first { $0.identifier == "fst.player.bands.empty.\(group.rawValue)" })
            #expect(empty.role == "AXStaticText", "\(context): a message, not a control: \(empty)")
            let spoken = [empty.label, empty.value].filter { !$0.isEmpty }.joined(separator: ", ")
            #expect(spoken.hasPrefix(Self.emptyTitle) && spoken.contains(Self.emptyHint),
                    "\(context): title then next step in one stop: \(empty)")
            let frame = try #require(nativeHostedAccessibilityFrame("fst.player.bands.empty.\(group.rawValue)", in: hosted.host))
            #expect(frame.height >= Self.minimumTarget - 0.5 && hosted.host.bounds.contains(frame),
                    "\(context): \(group) card is at least 44 pt tall, on the page: \(frame)")
        }
        #expect(!nodes.contains { $0.spokenName.hasPrefix("View All Bands") || $0.identifier.hasPrefix("fst.player-bands.row.") },
                "\(context): nothing to view all:\n\(Self.dump(nodes))")
        Self.expectNamed(hosted, context)
    }

    /// Operable without a pointer: AXPress on the title's View All opens the player's
    /// whole band list, and on a group's View All Bands opens it on that group.
    @Test func viewAllLinksOpenTheirListsByAccessibilityPress() async throws {
        for (identifier, pushed) in [
            (Self.linkID, "player-bands"), ("fst.player.bands.view-all.duos", "player-bands.duos"),
        ] {
            let hosted = try await Self.host(.withBands, .pass)
            defer { hosted.close() }
            try await Self.settle(on: "fst.player.bands.view-all.trios", hosted)
            try Self.press(identifier, in: hosted.host)
            try await Self.settle(on: Self.pushedPrefix + pushed, hosted)
            #expect(!hosted.nodes().contains { $0.identifier == Self.linkID }, "\(identifier) pushed its list")
        }
    }
}
#endif
