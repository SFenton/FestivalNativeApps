#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Back to Compete keeps its accessibility (issue #39, backfilled by #410)

// #39 stopped Back from View Full Leaderboard from restarting Compete's load: the page
// reset to its spinner, then the cards re-expanded and re-faded under the pop. Since then
// a plain return keeps the loaded page (`CompeteHubModel`'s `ReappearanceLoadGate`; the
// Rivals hub's sections use the same gate). `competeKeepsLoadedLeaderboardsWhenItReappears`
// pins the network side. These hosted checks (macOS host, `apple-ci`) pin what assistive
// technologies meet on the return, on every Apple platform, since `CompeteScreen` and
// `RivalsScreen` are the same SwiftUI on iPhone, iPad, iPhone Duo and Mac: at every
// sample from the moment the page reappears it reads exactly what it read before it
// left (the same elements, names, roles and identifiers, in the same order and at the
// same place on the scrolled page), never a "Loading" busy indicator, with each
// View Full Leaderboard still a named 44 pt button. The checks run at the standard and
// the largest accessibility text size and, on Compete, with fades on, system Reduce
// Motion and the app's Reduce Motion. A reload is made to hang (the leaderboard or rivals
// reads are held), so a return that reloads shows its spinner instead of racing past
// the samples. macOS keeps the font size, so the AX5 cases pin the tree only; the iPhone
// XCUITest `CompeteAccessibilityJourneyTests` taps the real Back at AX5.

// MARK: - Fixture

/// Holds the Rivals hub's rivals reads while `held` is set, forwarding every read to the
/// loopback fixture (`tools/mock_service.py`), and counts them.
actor HeldRivalsTransport: HTTPTransport {
    private let inner = URLSessionHTTPTransport()
    /// Whether a rivals read waits (until this is cleared).
    private(set) var held = false
    /// The rivals reads sent so far.
    private(set) var rivalsReads = 0

    /// Hold (or release) rivals reads from now on.
    ///
    /// - Parameter held: Whether a rivals read waits.
    func hold(_ held: Bool) {
        self.held = held
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        guard path.contains("/rivals/") || path.contains("/leaderboard-rivals/") else { return try await inner.send(request) }
        rivalsReads += 1
        while held { try await Task.sleep(for: .milliseconds(20)) }
        return try await inner.send(request)
    }
}

/// One element VoiceOver lands on, as compared across a return.
struct ReturnAXItem: Equatable, CustomStringConvertible {
    let role: String
    let name: String
    let identifier: String
    /// Its frame in the host's top-left points, if it has one.
    let frame: CGRect?

    init(_ node: MacAXNode, frame: CGRect?) {
        role = node.role
        name = node.spokenName
        identifier = node.identifier
        self.frame = frame
    }

    /// The same element at the same place, to within a point.
    static func == (lhs: ReturnAXItem, rhs: ReturnAXItem) -> Bool {
        guard lhs.role == rhs.role, lhs.name == rhs.name, lhs.identifier == rhs.identifier else { return false }
        switch (lhs.frame, rhs.frame) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return abs(left.minX - right.minX) <= 1 && abs(left.minY - right.minY) <= 1
                && abs(left.width - right.width) <= 1 && abs(left.height - right.height) <= 1
        default:
            return false
        }
    }

    var description: String {
        let place = frame.map { String(format: " @%.0f,%.0f %.0fx%.0f", $0.minX, $0.minY, $0.width, $0.height) } ?? ""
        return "\(role) '\(name)'" + (identifier.isEmpty ? "" : " #\(identifier)") + place
    }
}

/// Accessibility of Compete and the Rivals hub when Back returns to them (#39).
///
/// HIG VoiceOver: "be sure to keep labels current as interface and content change";
/// HIG Progress indicators: show one only while an operation is ongoing; HIG
/// Accessibility: 44×44 pt default control size on iOS/iPadOS.
@MainActor
@Suite(.serialized)
struct CompeteReturnAccessibilityTests {
    typealias Page = CompeteLoadingAccessibilityTests
    typealias Motion = CompeteLoadingAccessibilityTests.Motion

    /// A phone-height window, so the page scrolls and a return must keep its place.
    static let size = CGSize(width: 402, height: 800)
    /// How far the page is scrolled before it leaves.
    static let scrollOffset: CGFloat = 320
    /// How long the return is sampled: past the gates' 150 ms spinner-in.
    static let sampling: Duration = .milliseconds(900)
    /// The fewest samples taken, however busy the main actor is (a parallel run). A
    /// reload hangs on its held read, so its spinner stays for every later sample.
    static let minimumSamples = 8

    /// The page's own elements VoiceOver lands on, in its reading order (no containers or
    /// system scroller parts), with their frames.
    static func items(_ host: NSView) -> [ReturnAXItem] {
        Page.content(nativeHostedReachableElements(host)).map { ReturnAXItem($0.node, frame: $0.frame) }
    }

    static func dump(_ items: [ReturnAXItem]) -> String {
        items.map(\.description).joined(separator: "\n")
    }

    /// Run the disappear and appear cycle Back runs on iOS, then sample what VoiceOver
    /// reads until ``sampling`` ends and at least ``minimumSamples`` were taken.
    ///
    /// On iOS a `NavigationStack` push makes its root disappear and Back makes it appear
    /// again. A hosted macOS stack keeps its root appeared across a push, so the host
    /// leaves its window and comes back (the cycle `competeKeepsLoadedLeaderboardsWhenItReappears`
    /// uses; architecture "Reappearance keeps loaded content").
    ///
    /// - Parameters:
    ///   - window: The host's window.
    ///   - host: The page's hosting view.
    /// - Returns: The page as read at each sample from the moment it reappears.
    static func returnSamples(_ window: NSWindow, _ host: NSView) async throws -> [[ReturnAXItem]] {
        window.contentView = NSView()
        try await Task.sleep(for: .milliseconds(200))
        window.contentView = host
        let clock = ContinuousClock()
        let end = clock.now + sampling
        var samples: [[ReturnAXItem]] = []
        repeat {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            samples.append(items(host))
            try await Task.sleep(for: .milliseconds(30))
        } while clock.now < end || samples.count < minimumSamples
        return samples
    }

    /// Expect every sample of the return to read `before` exactly: no spinner, no
    /// "Loading" element, nothing gone, added, renamed, reordered or moved.
    static func expectUnchanged(
        _ samples: [[ReturnAXItem]], _ before: [ReturnAXItem], _ context: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for (index, sample) in samples.enumerated() {
            let loading = sample.filter { $0.role == "AXBusyIndicator" || $0.name.hasPrefix("Loading") }
            #expect(loading.isEmpty, "\(context): no spinner at sample \(index):\n\(dump(sample))",
                    sourceLocation: sourceLocation)
            guard sample == before else {
                let changed = zip(before, sample).first { $0 != $1 }.map { "\($0) → \($1)" } ?? "count \(before.count) → \(sample.count)"
                Issue.record("\(context): sample \(index) reads a different page (\(changed)):\n\(dump(sample))",
                             sourceLocation: sourceLocation)
                return
            }
        }
    }

    // MARK: Compete

    /// Back to Compete reads the page it left, at every moment of the return: the
    /// Leaderboards heading, each board's heading, rows and named 44 pt View Full
    /// Leaderboard button, then the Rivals sections, at the same scrolled place and with
    /// no "Loading Compete" spinner, at the standard and the largest accessibility text
    /// size and with Reduce Motion from the system or the app.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5], Motion.allCases)
    func backToCompeteReadsTheSamePageWithoutASpinner(_ typeSize: DynamicTypeSize, _ motion: Motion) async throws {
        let context = "\(typeSize), \(motion)"
        let hosted = try await Page.host(.pass, typeSize: typeSize, motion: motion, size: Self.size)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            let tree = macAccessibilityTree(hosted.host)
            return !tree.contains { $0.identifier == Page.spinnerID }
                && tree.contains { $0.spokenName == "View Full Leaderboard, Bass" }
                && tree.contains { $0.spokenName == "Bass Rivals" }
        }
        try FadeInScopeAccessibilityTests.scroll(hosted.host, to: Self.scrollOffset)
        // Let entrance fades end, so the page read before leaving is the settled one.
        try await Task.sleep(for: .milliseconds(1200))
        let before = Self.items(hosted.host)
        let boards = Page.boards.map(\.name)
        #expect(before.filter { $0.role == "AXHeading" }.map(\.name)
            == ["Leaderboards"] + boards + ["Rivals"] + boards.map { "\($0) Rivals" },
            "\(context): the loaded page before leaving:\n\(Self.dump(before))")
        #expect(before.contains { $0.frame.map { $0.minY < 0 } ?? false },
                "\(context): the page is scrolled before leaving:\n\(Self.dump(before))")

        // A reload would now hang on its spinner.
        await hosted.transport.set(.hold)
        let samples = try await Self.returnSamples(hosted.window, hosted.host)
        Self.expectUnchanged(samples, before, context)
        for board in Page.boards {
            let id = "fst.compete.leaderboard-card.\(board.id).view-all"
            let button = try #require(before.first { $0.name == "View Full Leaderboard, \(board.name)" })
            #expect(button.role == "AXButton", "\(context): \(button)")
            Page.expectTarget(hosted, id, "\(context), after Back")
        }
        let after = Self.items(hosted.host)
        #expect(after.allSatisfy { !$0.name.isEmpty }, "\(context): nothing unnamed:\n\(Self.dump(after))")
        #expect(macAccessibilityFindings(hosted.tree()).isEmpty, "\(context)")
        await hosted.transport.set(.pass)
    }

    // MARK: Rivals hub

    /// One hosted Rivals hub for `fixture-riv` with Lead and Bass shown.
    struct RivalsHosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let transport: HeldRivalsTransport
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }
    }

    /// Host the Rivals hub on `tab` for `fixture-riv`, with Lead and Bass shown, so it
    /// has its Common, Combo and per-instrument sections (Song) or per-instrument boards
    /// (Leaderboard).
    static func hostRivals(_ tab: RivalsScreen.Tab, typeSize: DynamicTypeSize) async throws -> RivalsHosted {
        let transport = HeldRivalsTransport()
        let baseURL = try await RivalsMockService.shared.baseURL()
        let client = try FestivalAPI(baseURL: baseURL, transport: transport)
        let suiteName = "fst.tests.rivals-return-a11y.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        let identity: [String: String] = ["accountId": "fixture-riv", "displayName": "Fixture Viewer"]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        for key in Page.allInstrumentKeys { storage.set(Page.visibleKeys.contains(key), forKey: key) }
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        let host = nativeHostedView(
            AnyView(
                NavigationStack { RivalsScreen(session: session, tab: tab) }
                    .environment(\.dynamicTypeSize, typeSize)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        return RivalsHosted(
            host: host, window: nativeHostedWindow(host, size: size), transport: transport,
            storage: storage, suiteName: suiteName
        )
    }

    /// The Rivals hub's tabs, as test arguments.
    enum RivalsTab: String, CaseIterable, CustomTestStringConvertible {
        case song
        case leaderboard

        var tab: RivalsScreen.Tab { self == .song ? .song : .leaderboard }
        var testDescription: String { rawValue }
    }

    /// Back to the Rivals hub (from a rival or View All Rivals) reads the page it left at
    /// every moment of the return, at the same scrolled place, with no section dropping
    /// to its "Loading" spinner, no second rivals read and each card's View All Rivals a
    /// named 44 pt button, on either tab and at the standard and the largest
    /// accessibility text size.
    @Test(arguments: RivalsTab.allCases, [DynamicTypeSize.large, .accessibility5])
    func backToTheRivalsHubReadsTheSamePageWithoutASpinner(_ tab: RivalsTab, _ typeSize: DynamicTypeSize) async throws {
        let context = "\(tab), \(typeSize)"
        let hosted = try await Self.hostRivals(tab.tab, typeSize: typeSize)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            let tree = macAccessibilityTree(hosted.host)
            return !tree.contains { $0.role == "AXBusyIndicator" || $0.spokenName.hasPrefix("Loading") }
                && tree.contains { $0.identifier.hasPrefix("fst.rivals.row.") }
        }
        // The Song tab's four cards scroll; the Leaderboard tab's two fit the window.
        if tab == .song { try FadeInScopeAccessibilityTests.scroll(hosted.host, to: Self.scrollOffset) }
        try await Task.sleep(for: .milliseconds(800))
        let before = Self.items(hosted.host)
        #expect(tab != .song || before.contains { $0.frame.map { $0.minY < 0 } ?? false },
                "\(context): the page is scrolled before leaving:\n\(Self.dump(before))")
        #expect(!before.contains { $0.role == "AXBusyIndicator" || $0.name.hasPrefix("Loading") },
                "\(context): loaded before leaving:\n\(Self.dump(before))")
        #expect(before.contains { $0.identifier.hasPrefix("fst.rivals.row.") },
                "\(context): rivals rows before leaving:\n\(Self.dump(before))")
        let readsBeforeLeaving = await hosted.transport.rivalsReads

        await hosted.transport.hold(true)
        let samples = try await Self.returnSamples(hosted.window, hosted.host)
        Self.expectUnchanged(samples, before, context)
        #expect(await hosted.transport.rivalsReads == readsBeforeLeaving,
                "\(context): the return reads no rivals again")
        let after = Self.items(hosted.host)
        let viewAll = after.filter { $0.name.hasPrefix("View All Rivals, ") }
        #expect(viewAll.count >= (tab == .song ? 4 : 2), "\(context): every card ends with View All Rivals:\n\(Self.dump(after))")
        for button in viewAll {
            #expect(button.role == "AXButton", "\(context): \(button)")
            let frame = try #require(button.frame, "\(context): \(button) has a frame")
            #expect(frame.width >= Page.minimumTarget - 0.5 && frame.height >= Page.minimumTarget - 0.5,
                    "\(context): \(button) is a 44×44 pt target")
        }
        // The macOS segmented Picker's radio group is a container titled by its "View"
        // label; its segments carry the names.
        #expect(after.filter { $0.role != "AXRadioGroup" }.allSatisfy { !$0.name.isEmpty },
                "\(context): nothing unnamed:\n\(Self.dump(after))")
        #expect(macAccessibilityFindings(macAccessibilityTree(hosted.host, navigationOrder: true)).isEmpty, "\(context)")
        await hosted.transport.hold(false)
    }
}
#endif
