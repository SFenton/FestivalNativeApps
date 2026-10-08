#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Rival Detail accessibility during a publish freeze (#95, backfilled by #444)

/// #95 made a rival open while the service publishes: the Rivals hub opens a rival
/// with the Settings scope (Lead + Bass → combo `03`), and a frozen detail read (503)
/// is rebuilt from `/rivals/all`; without samples the page keeps the auto-retry state.
/// These hosted checks pin what that page exposes to VoiceOver, Voice Control, Full
/// Keyboard Access and Dynamic Type. `RivalDetailScreen`, `RivalSongRowContent`,
/// `RivalInstrumentSongCard` and `ServiceStatusView` are the same SwiftUI on iPhone,
/// iPad, iPhone Duo and Mac.
///
/// HIG Accessibility: "Provide VoiceOver descriptions for all interface elements";
/// "Never rely on color alone" (nor an icon alone); iOS/iPadOS default control size
/// 44×44 pt. HIG Typography: "Keep text truncation to a minimum as font size
/// increases". HIG Loading: "Show something quickly".
@MainActor
@Suite(.serialized)
struct RivalDetailAccessibilityTests {
    // MARK: - Fixture

    /// The selected player, the rival and the Settings-visible instruments.
    static let player = (id: "player1", name: "Fixture Viewer")
    static let rival = (id: "rival9", name: "Rival Nine")
    static let visible: [Instrument] = [.lead, .bass]

    /// `/rivals/all` for `player1`: Rival Nine on Lead and Bass of Fixture Pulse (so
    /// the combo scope lists the same song twice) and on Lead of Fixture Orbit. Titles
    /// come from `contracts/fixtures/songs-demo.json`.
    nonisolated static let rivalsAll = Data("""
    {"accountId":"player1","songs":["fixture-pulse","fixture-orbit"],"combos":[{"combo":"03","above":[
     {"accountId":"rival9","displayName":"Rival Nine","direction":"above","sharedSongCount":3,
      "aheadCount":1,"behindCount":2,"rivalScore":1.0,"samples":[
       {"s":0,"i":"Solo_Guitar","ur":10,"rr":11,"us":900,"rs":890},
       {"s":0,"i":"Solo_Bass","ur":12,"rr":10,"us":800,"rs":850},
       {"s":1,"i":"Solo_Guitar","ur":3,"rr":20,"us":990,"rs":700}]}],"below":[]}]}
    """.utf8)

    /// What a hosted page's `/rivals/all` read answers.
    enum Snapshot {
        /// The precomputed samples above.
        case available
        /// No snapshot (404): the page keeps the freeze's retry state.
        case missing
    }

    /// Keyless public reads for one player while the service publishes: every rival
    /// detail read is the freeze's 503, `/rivals/all` and the catalogue answer.
    actor FrozenTransport: HTTPTransport {
        let snapshot: Snapshot
        let catalogue: Data
        private var holdsSnapshot: Bool
        private(set) var paths: [String] = []

        /// - Parameters:
        ///   - snapshot: What `/rivals/all` answers.
        ///   - catalogue: Songs envelope for titles and song links.
        ///   - holdsSnapshot: Keep `/rivals/all` pending until ``release()`` (loading state).
        init(snapshot: Snapshot, catalogue: Data, holdsSnapshot: Bool = false) {
            self.snapshot = snapshot
            self.catalogue = catalogue
            self.holdsSnapshot = holdsSnapshot
        }

        /// Let a held `/rivals/all` read answer.
        func release() { holdsSnapshot = false }

        /// Answer one native GET; refuse writes, the privileged key and profile headers.
        ///
        /// - Parameter request: One request the page makes.
        /// - Returns: Publication, catalogue, `/rivals/all`, or the freeze's 503.
        /// - Throws: An unsafe request.
        func send(_ request: URLRequest) async throws -> HTTPResult {
            guard let url = request.url, request.httpMethod == "GET",
                  request.value(forHTTPHeaderField: "X-API-Key") == nil,
                  request.allHTTPHeaderFields?.keys.contains(where: {
                      $0.lowercased().hasPrefix("x-fst-selected-")
                  }) != true else {
                throw FestivalAPIError.invalidResponse
            }
            paths.append(url.path)
            let pinned = ["X-FST-Publication-Id": "7"]
            switch url.path {
            case "/api/publication":
                return HTTPResult(status: 200, data: Data("""
                {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
                 "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
                """.utf8))
            case "/api/songs":
                return HTTPResult(status: 200, data: catalogue, headers: pinned)
            case "/api/player/player1/rivals/all":
                while holdsSnapshot { try await Task.sleep(for: .milliseconds(20)) }
                switch snapshot {
                case .available: return HTTPResult(status: 200, data: RivalDetailAccessibilityTests.rivalsAll, headers: pinned)
                case .missing: return HTTPResult(status: 404, data: Data())
                }
            default:
                return HTTPResult(
                    status: 503, data: Data(),
                    headers: ["Retry-After": "30", ServiceFreezeReason.header: "post-process"]
                )
            }
        }
    }

    /// One hosted Rival Detail page.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let transport: FrozenTransport
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }
    }

    /// Storage with the player selected, Lead and Bass visible and Reduce Motion on.
    static func storage() throws -> (UserDefaults, String) {
        let suiteName = "fst.tests.rival-detail-a11y.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        let identity = ["accountId": player.id, "displayName": player.name]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        for instrument in Instrument.allCases {
            storage.set(visible.contains(instrument), forKey: "fst.settings.show\(settingsSuffix(instrument))")
        }
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        return (storage, suiteName)
    }

    /// The `fst.settings.show…` suffix `VisibleInstrumentsReader` reads.
    static func settingsSuffix(_ instrument: Instrument) -> String {
        switch instrument {
        case .lead: "Lead"
        case .bass: "Bass"
        case .drums: "Drums"
        case .vocals: "Vocals"
        case .proLead: "ProLead"
        case .proBass: "ProBass"
        case .karaoke: "Karaoke"
        case .proCymbals: "ProCymbals"
        case .proDrums: "ProDrums"
        }
    }

    /// Host Rival Detail opened from the hub (Settings scope) on a phone-width page.
    ///
    /// - Parameters:
    ///   - snapshot: What `/rivals/all` answers.
    ///   - typeSize: Dynamic Type size for the page.
    ///   - holdsSnapshot: Keep the page loading until the transport is released.
    ///   - clock: The retry countdown's clock (a manual one never retries on its own).
    /// - Returns: The host before any wait; callers settle on the state they assert.
    static func host(
        _ snapshot: Snapshot, typeSize: DynamicTypeSize = .large, holdsSnapshot: Bool = false,
        clock: any Clock<Duration> = ManualTestClock()
    ) throws -> Hosted {
        let (storage, suiteName) = try storage()
        let transport = FrozenTransport(
            snapshot: snapshot, catalogue: try shopFixtureBytes().catalogue, holdsSnapshot: holdsSnapshot
        )
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        let size = CGSize(width: 402, height: 1600)
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    RivalDetailScreen(
                        session: session, rivalId: rival.id, name: rival.name,
                        scope: RivalDetailScopes.hubScope(visible: visible)
                    )
                }
                .frame(width: size.width, height: size.height)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.serviceRetryClock, clock)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        return Hosted(host: host, window: window, transport: transport, storage: storage, suiteName: suiteName)
    }

    /// Host the fallback-loaded page and wait for every song row.
    static func hostLoaded(_ typeSize: DynamicTypeSize = .large) async throws -> Hosted {
        let hosted = try host(.available, typeSize: typeSize)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(60)) {
            let nodes = macAccessibilityTree(hosted.host).filter(\.isElement)
            return songRows(nodes).count >= 3 && nodes.contains { $0.role == "AXButton" && $0.spokenName.contains("Fixture Pulse") }
        }
        return hosted
    }

    /// The song comparison rows, in reading order.
    static func songRows(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.isElement && $0.spokenName.contains("you rank") }
    }

    /// The category "View All" links, in reading order.
    static func viewAlls(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.isElement && $0.identifier.hasPrefix("fst.rival-detail.category.") && $0.identifier.hasSuffix(".view-all") }
    }

    /// Frame of the first element whose spoken name is exactly `name`.
    static func frame(named name: String, in host: NSView) -> CGRect? {
        nativeHostedAccessibilityElement(in: host) { element in
            let spoken = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
                .map { nativeHostedAccessibilityString(element, $0) }.first { !$0.isEmpty } ?? ""
            return spoken == name && (element.value(forKey: "isAccessibilityElement") as? Bool) == true
        }.flatMap { nativeHostedAccessibilityFrame(of: $0, in: host) }
    }

    // MARK: - Names, roles and state

    /// The rebuilt comparison reads like a normal one: category titles are headings,
    /// each song row is a button naming the song, its instrument (the combo scope lists
    /// Fixture Pulse on Lead and on Bass, told apart only by the icon on screen) and both
    /// ranks; each category's View All says which card it opens; nothing is unnamed and
    /// no spinner or error stays behind.
    @Test func frozenRivalDetailNamesRowsHeadingsAndActions() async throws {
        let hosted = try await Self.hostLoaded()
        defer { hosted.close() }
        #expect(await hosted.transport.paths.contains("/api/player/player1/rivals/all"), "the freeze fallback built this page")
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "rival-detail-frozen-large")
        let dump = nodes.map(\.description).joined(separator: "\n")
        let elements = nodes.filter(\.isElement)

        #expect(!elements.contains { $0.spokenName.contains("Loading rival detail") }, "no spinner left:\n\(dump)")
        #expect(!elements.contains { $0.identifier.hasPrefix("fst.service-status") }, "no error state:\n\(dump)")

        let headings = elements.filter { $0.role == "AXHeading" }.map(\.spokenName)
        #expect(headings.contains("Closest Battles"), "category titles are headings: \(headings)\n\(dump)")

        let rows = Self.songRows(elements)
        #expect(rows.count >= 3, "\(dump)")
        for row in rows {
            #expect(row.role == "AXButton", "a song row opens Song Detail: \(row)")
            #expect(row.spokenName.contains("you rank") && row.spokenName.contains("\(Self.rival.name) ranks"), "\(row)")
        }
        let pulse = rows.filter { $0.spokenName.hasPrefix("Fixture Pulse") }.map(\.spokenName)
        #expect(Set(pulse) == [
            "Fixture Pulse, Lead, you rank 10, Rival Nine ranks 11",
            "Fixture Pulse, Bass, you rank 12, Rival Nine ranks 10",
        ], "the Lead and Bass rows of one song read differently: \(pulse)")
        #expect(rows.contains { $0.spokenName == "Fixture Orbit, Lead, you rank 3, Rival Nine ranks 20" }, "\(dump)")

        let links = Self.viewAlls(elements)
        #expect(!links.isEmpty, "\(dump)")
        for link in links {
            #expect(["AXButton", "AXLink"].contains(link.role), "\(link)")
            #expect(link.spokenName.hasPrefix("View All, ") && link.spokenName.count > "View All, ".count, "\(link)")
        }
        // The instrument icon is part of its row, not a separate stop.
        #expect(!elements.contains { $0.role == "AXImage" && ["Lead", "Bass"].contains($0.spokenName) }, "\(dump)")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Reading order and target size

    /// Each category reads heading → its rows → its View All, cards top to bottom, and
    /// every row and View All is at least a 44 pt target inside the page.
    @Test func frozenRivalDetailReadsInVisualOrderWithFullSizeTargets() async throws {
        let hosted = try await Self.hostLoaded()
        defer { hosted.close() }
        let host = hosted.host
        let elements = macAccessibilityTree(host).filter(\.isElement)
        let dump = elements.map(\.description).joined(separator: "\n")
        let headingIndices = elements.indices.filter { elements[$0].role == "AXHeading" && elements[$0].spokenName != Self.rival.name }
        let viewAllIndices = elements.indices.filter { Self.viewAlls([elements[$0]]).count == 1 }
        #expect(headingIndices.count == viewAllIndices.count && !headingIndices.isEmpty, "\(dump)")
        for (card, (heading, viewAll)) in zip(headingIndices, viewAllIndices).enumerated() {
            #expect(heading < viewAll, "card \(card): heading before its View All")
            let rows = elements[heading..<viewAll].filter { $0.spokenName.contains("you rank") }
            #expect(!rows.isEmpty, "card \(card): rows between its heading and its View All\n\(dump)")
            #expect(elements[viewAll].spokenName == "View All, \(elements[heading].spokenName)",
                    "card \(card): View All names its own card")
            if card + 1 < headingIndices.count {
                #expect(viewAll < headingIndices[card + 1], "card \(card) ends before the next heading")
            }
        }

        var previous = -CGFloat.infinity
        for title in ["Closest Battles"] {
            let heading = try #require(Self.frame(named: title, in: host), "\(title)")
            #expect(heading.minY > previous)
            previous = heading.minY
        }
        let rowFrames = try Self.songRows(elements).map { row in
            try #require(Self.frame(named: row.spokenName, in: host), "\(row.description)")
        }
        for frame in rowFrames {
            #expect(frame.height >= 44 - 0.5, "a song row is a 44 pt target: \(frame)")
            #expect(frame.minX >= -0.5 && frame.maxX <= host.bounds.width + 0.5, "inside the page: \(frame)")
        }
        for id in Self.viewAlls(elements).map(\.identifier) {
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: host), "\(id)")
            #expect(frame.height >= 44 - 0.5 && frame.width >= 44, "\(id) is a 44 pt target: \(frame)")
            #expect(frame.maxX <= host.bounds.width + 0.5, "\(id) inside the page: \(frame)")
        }
    }

    // MARK: - Text scaling

    /// At AX5 the rows keep their full names, grow with the text (the rank comparison
    /// stacks one part per line) and stay inside the page; View All stays reachable.
    @Test func frozenRivalDetailGrowsAtAccessibilitySizes() async throws {
        let name = "Fixture Orbit, Lead, you rank 3, Rival Nine ranks 20"
        let standard = try await Self.hostLoaded(.large)
        let standardRow = try #require(Self.frame(named: name, in: standard.host))
        standard.close()

        let large = try await Self.hostLoaded(.accessibility5)
        defer { large.close() }
        let host = large.host
        let elements = macAccessibilityTree(host).filter(\.isElement)
        macAccessibilityDump(elements, name: "rival-detail-frozen-ax5")
        let row = try #require(Self.frame(named: name, in: host), "the AX5 row keeps its whole name")
        #expect(row.height >= standardRow.height * 1.35, "the row grows with its text: \(standardRow.height) → \(row.height)")
        #expect(row.minX >= -0.5 && row.maxX <= host.bounds.width + 0.5, "no sideways overflow: \(row)")
        for node in Self.songRows(elements) {
            #expect(node.role == "AXButton", "\(node)")
        }
        let links = Self.viewAlls(elements)
        #expect(!links.isEmpty)
        for id in links.map(\.identifier) {
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: host), "\(id)")
            #expect(frame.height >= 44 - 0.5 && frame.maxX <= host.bounds.width + 0.5, "\(id): \(frame)")
        }
        #expect(macAccessibilityFindings(elements) == [])
    }

    // MARK: - Loading and retry states

    /// While the snapshot read is pending, the page shows one named loading indicator
    /// (no rows, no error); it leaves the tree once the rebuilt rows arrive.
    @Test func frozenRivalDetailAnnouncesLoadingOnce() async throws {
        let hosted = try Self.host(.available, holdsSnapshot: true)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(60)) {
            macAccessibilityTree(hosted.host).contains { $0.isElement && $0.spokenName == "Loading rival detail" }
        }
        let loading = macAccessibilityTree(hosted.host).filter(\.isElement)
        #expect(loading.filter { $0.spokenName == "Loading rival detail" }.count == 1, "one named spinner")
        #expect(Self.songRows(loading).isEmpty)
        #expect(!loading.contains { $0.identifier.hasPrefix("fst.service-status") })

        await hosted.transport.release()
        try await nativeHostedSettle(hosted.host, timeout: .seconds(60)) {
            Self.songRows(macAccessibilityTree(hosted.host)).count >= 3
        }
        #expect(!macAccessibilityTree(hosted.host).contains { $0.isElement && $0.spokenName == "Loading rival detail" })
    }

    /// Without a snapshot for the rival, the page keeps the freeze state: a heading, the
    /// countdown read as a sentence, then a named Retry Now button at least 44 pt, in that
    /// order, at standard and AX5 sizes.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func frozenRivalDetailWithoutSnapshotOffersNamedRetry(typeSize: DynamicTypeSize) async throws {
        let hosted = try Self.host(.missing, typeSize: typeSize)
        defer { hosted.close() }
        let host = hosted.host
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            let ids = nativeHostedAccessibility(host).identifiers
            return ids.contains("fst.service-status.retry") && ids.contains("fst.service-status.countdown")
        }
        let elements = macAccessibilityTree(host).filter(\.isElement)
        macAccessibilityDump(elements, name: "rival-detail-frozen-retry-\(typeSize)")
        let dump = elements.map(\.description).joined(separator: "\n")
        func index(_ id: String) throws -> Int {
            try #require(elements.firstIndex { $0.identifier == id }, "\(id)\n\(dump)")
        }
        let title = elements[try index("fst.service-status.title")]
        let countdown = elements[try index("fst.service-status.countdown")]
        let retry = elements[try index("fst.service-status.retry")]
        #expect(title.role == "AXHeading" && title.spokenName == "Scores are updating", "\(title)")
        // The delay starts at Retry-After and backs off, so only the sentence is fixed.
        #expect(countdown.spokenName.wholeMatch(of: /Trying again automatically in \d+ seconds?/) != nil, "\(countdown)")
        #expect(retry.role == "AXButton" && retry.spokenName == "Retry Now", "\(retry)")
        #expect(try index("fst.service-status.title") < index("fst.service-status.countdown"))
        #expect(try index("fst.service-status.countdown") < index("fst.service-status.retry"))
        #expect(Self.songRows(elements).isEmpty)
        #expect(!elements.contains { $0.spokenName == "Loading rival detail" })

        let frame = try #require(nativeHostedAccessibilityFrame("fst.service-status.retry", in: host))
        #expect(frame.width >= 44 - 0.5 && frame.height >= 44 - 0.5, "Retry Now is a 44 pt target: \(frame)")
        #expect(frame.minX >= -0.5 && frame.maxX <= host.bounds.width + 0.5, "Retry Now inside the page: \(frame)")
        #expect(macAccessibilityFindings(elements) == [])
    }

    // MARK: - Rivals hub row (VoiceOver and keyboard)

    /// Records what the hub row's keyboard activation pushes.
    final class PushRecorder {
        var pushed: [AppRoute] = []
    }

    /// The hub row that #95 points at the Settings scope is one named button ("name,
    /// N songs ahead, M songs behind", no separate dot or chevron stop) at least 44 pt
    /// tall, and on the Mac ↓ then Return opens the same Settings-scope detail a click does.
    @Test func rivalsHubRowIsANamedButtonThatOpensTheSettingsScope() async throws {
        let (storage, suiteName) = try Self.storage()
        defer { storage.removePersistentDomain(forName: suiteName) }
        let list = try JSONDecoder().decode(RivalsListResponse.self, from: Data("""
        {"combo":"Solo_Guitar","above":[{"accountId":"rival9","displayName":"Rival Nine","rivalScore":1.0,
          "sharedSongCount":3,"aheadCount":1,"behindCount":2,"avgSignedDelta":-1.0}],"below":[]}
        """.utf8))
        let scope = RivalDetailScopes.hubScope(visible: Self.visible)
        let recorder = PushRecorder()
        let size = CGSize(width: 402, height: 400)
        let host = NSHostingView(rootView: NativeHostedRoot(
            content: AnyView(
                NavigationStack {
                    ScrollView {
                        RivalInstrumentSongCard(instrument: .lead, state: .loaded(list), detailScope: scope) {}
                            .padding(.horizontal, 16)
                    }
                    .modifier(MacKeyboardNavigation(
                        selection: nil, select: nil, push: { recorder.pushed.append($0) }, isTop: true
                    ))
                }
                .frame(width: size.width, height: size.height)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
            ),
            forceGlassFallback: true
        ))
        nativeHostedEnableAccessibility()
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, timeout: .seconds(30)) {
            nativeHostedAccessibilityFrame("fst.rivals.row.rival9", in: host) != nil
        }
        let elements = macAccessibilityTree(host).filter(\.isElement)
        let row = try #require(elements.first { $0.identifier == "fst.rivals.row.rival9" })
        #expect(row.role == "AXButton", "\(row)")
        #expect(row.spokenName == "Rival Nine, 2 songs ahead, 1 songs behind", "\(row)")
        #expect(!elements.contains { $0.role == "AXImage" && $0.spokenName.contains("chevron") })
        let frame = try #require(nativeHostedAccessibilityFrame("fst.rivals.row.rival9", in: host))
        #expect(frame.height >= 44 - 0.5, "the hub row is a 44 pt target: \(frame)")
        #expect(macAccessibilityFindings(macAccessibilityTree(host)) == [])

        Self.sendKey("down", to: window)
        _ = try await nativeHostedSettle(host)
        Self.sendKey("return", to: window)
        _ = try await nativeHostedSettle(host) { !recorder.pushed.isEmpty }
        #expect(recorder.pushed == [.rivalDetail(rivalId: "rival9", name: "Rival Nine", scope: scope)])
        if case let .combo(token, _) = scope {
            #expect(token == "03", "Lead + Bass opens the Settings combo")
        } else {
            Issue.record("the hub opens a combo scope: \(scope)")
        }
    }

    /// Deliver a key press through the window, as AppKit does.
    static func sendKey(_ name: String, to window: NSWindow) {
        guard let key = MacDebugHooks.keyEvent(named: name) else { return }
        let flags: NSEvent.ModifierFlags = key.keyCode >= 115 ? [.function, .numericPad] : []
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: key.characters,
                charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.keyCode
            ) {
                window.sendEvent(event)
            }
        }
    }
}
#endif
