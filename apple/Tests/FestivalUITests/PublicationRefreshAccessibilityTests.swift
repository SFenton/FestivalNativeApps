#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
import FestivalDesign
@testable import FestivalUI

// MARK: - Publication refresh accessibility (issue #325, backfilled by #471)

// #325 moved ``PublicationRefreshBoundary``'s spinner, VoiceOver page anchor and
// `@AccessibilityFocusState` into an overlay layer that is always mounted over the page
// (`PublicationRefreshFocusLayer`), so a focus-store update no longer rebuilds a whole
// Songs list mid-scroll. These hosted checks (macOS host, `apple-ci`) pin what that
// overlay exposes on every Apple platform, since the boundary is the same SwiftUI on
// iPhone, iPad, iPhone Duo and Mac: at rest it adds no element and takes no clicks, so
// the page reads and responds as if it were not there; during a rollover it reads as one
// busy indicator named "Loading new scores" with no stale rows and the outside chrome
// still named and operable; after the reveal the new rows read in visual order; text
// inside grows whole at AX5; and Reduce Motion keeps the spinner's minimum (pattern
// `load-transition` R3, R9). The page anchor needs VoiceOver or the Debug
// `FST_UI_TEST_PAGE_ANCHOR` launch override, so its label and value are covered by the
// iPhone journeys (`SongsTopScrollAccessibilityJourneyTests`, `SongsJourneyTests`).

// MARK: - Fixture

/// A page shaped like Songs around the boundary: a tool button outside it (Songs' Sort
/// and search stay outside, `title: "Songs"`), and inside a short section heading over
/// rows that read the **live** publication, as a rebuilt page does, so the reveal shows
/// whether the new generation is what VoiceOver reads.
struct PublicationRefreshA11yPage: View {
    let session: FestivalSession
    /// How long the page's `prepare` takes for a new publication (nil: no `prepare`).
    var prepareDelay: Duration? = nil

    static let rowCount = 3
    static let toolID = "fst.pub-a11y.tool"
    static let headingID = "fst.pub-a11y.heading"
    static let spinnerID = "fst.publication.refreshing"
    static let spinnerLabel = "Loading new scores"
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    static let minimumTarget: CGFloat = 44

    /// The identifier of row `index`.
    nonisolated static func rowID(_ index: Int) -> String { "fst.pub-a11y.row.\(index)" }

    /// The spoken name of row `index` in publication `publication`.
    nonisolated static func rowLabel(_ index: Int, _ publication: Int?) -> String {
        "Song \(index + 1), publication \(publication.map(String.init) ?? "none")"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {} label: {
                ReloadGateA11yText(text: "Sort", style: .body)
                    .foregroundStyle(.white)
                    .frame(minWidth: Self.minimumTarget, minHeight: Self.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(Self.toolID)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 16)

            PublicationRefreshBoundary(session: session, title: "Songs", prepare: prepareDelay.map { delay in
                { _ in try? await Task.sleep(for: delay) }
            }) {
                PublicationRefreshA11yRows(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BrandTokens.cardBackground)
    }
}

/// The boundary's content: a short "#" heading, so the first row starts inside the top
/// 44 pt strip where the page anchor lies, then row buttons that count their presses.
struct PublicationRefreshA11yRows: View {
    let session: FestivalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReloadGateA11yText(text: "#", style: .body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 24)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(PublicationRefreshA11yPage.headingID)
            ForEach(0..<PublicationRefreshA11yPage.rowCount, id: \.self) { index in
                Button { PublicationRefreshA11yPresses.shared.count[index, default: 0] += 1 } label: {
                    ReloadGateA11yText(text: "Song \(index + 1)", style: .body)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: PublicationRefreshA11yPage.minimumTarget, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PublicationRefreshA11yPage.rowLabel(index, session.publicationId))
                .accessibilityIdentifier(PublicationRefreshA11yPage.rowID(index))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Row presses, by row index (the rows are rebuilt on every reveal).
@MainActor
final class PublicationRefreshA11yPresses {
    static let shared = PublicationRefreshA11yPresses()
    var count: [Int: Int] = [:]
}

// MARK: - Tests

@MainActor
@Suite(.serialized)
struct PublicationRefreshAccessibilityTests {
    typealias Page = PublicationRefreshA11yPage
    typealias Motion = ReloadGateAccessibilityTests.Motion

    /// One hosted page and its session.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let session: FestivalSession
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// The page's own elements VoiceOver reaches through `accessibilityChildren`, in
        /// reading order, after one layout pass (no waiting, so no timed step runs).
        func elements() -> [MacAXNode] {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            return ReloadGateAccessibilityTests.reachable(host).filter {
                $0.identifier.hasPrefix("fst.pub-a11y.") || $0.identifier.hasPrefix("fst.publication.")
            }
        }
    }

    /// Host the fixture page on a phone-width window at publication 7.
    ///
    /// - Parameters:
    ///   - typeSize: Dynamic Type size for the page.
    ///   - motion: Fade and Reduce Motion settings.
    /// - Returns: The settled page.
    static func host(
        typeSize: DynamicTypeSize = .large, motion: Motion = .instant, prepareDelay: Duration? = nil
    ) async throws -> Hosted {
        let suiteName = "fst-publication-refresh-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        try await session.observe(publicationId: 7)
        let size = CGSize(width: 390, height: 700)
        let host = nativeHostedView(
            AnyView(
                Page(session: session, prepareDelay: prepareDelay)
                    .environment(\.festivalFadeInEnabled, motion != .instant)
                    .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
                    .environment(\.dynamicTypeSize, typeSize)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        let hosted = Hosted(
            host: host, window: nativeHostedWindow(host, size: size), session: session,
            storage: storage, suiteName: suiteName
        )
        try await settleOnRows(hosted, publication: 7)
        return hosted
    }

    /// Wait until the rows of `publication` are in the tree and the spinner has left it.
    static func settleOnRows(
        _ hosted: Hosted, publication: Int, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let labels = (0..<Page.rowCount).map { Page.rowLabel($0, publication) }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30), sourceLocation: sourceLocation) {
            let nodes = hosted.elements()
            return rows(nodes).map(\.spokenName) == labels
                && spinners(nodes).isEmpty
        }
    }

    /// Poll briefly (10 ms steps, without the settle's capture) until the refresh
    /// spinner is in the tree; the Reduce Motion hold keeps it there for 400 ms.
    ///
    /// - Returns: The page's elements at that moment.
    static func waitForSpinner(
        _ hosted: Hosted, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> [MacAXNode] {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline {
            let nodes = hosted.elements()
            if !spinners(nodes).isEmpty { return nodes }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the refresh spinner never appeared", sourceLocation: sourceLocation)
        return hosted.elements()
    }

    static func rows(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.identifier.hasPrefix("fst.pub-a11y.row.") }
    }

    static func spinners(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.identifier == Page.spinnerID }
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    /// The page's reading order at rest: the tool, the heading, then the rows.
    static let restingOrder = [Page.toolID, Page.headingID] + (0..<Page.rowCount).map(Page.rowID)

    /// Expect `ids` to be at least 44×44 pt targets lying wholly on the page.
    static func expectTargets(
        _ hosted: Hosted, _ ids: [String], _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        hosted.host.layoutSubtreeIfNeeded()
        let page = hosted.host.bounds.insetBy(dx: -0.5, dy: -0.5)
        for id in ids {
            guard let frame = nativeHostedAccessibilityFrame(id, in: hosted.host) else {
                Issue.record("\(context): \(id) has no accessibility frame", sourceLocation: sourceLocation)
                continue
            }
            let minimum = Page.minimumTarget - 0.5
            #expect(frame.width >= minimum && frame.height >= minimum,
                    "\(context): \(id) is a 44×44 pt target: \(frame)", sourceLocation: sourceLocation)
            #expect(page.contains(frame), "\(context): \(id) lies wholly on the page: \(frame)", sourceLocation: sourceLocation)
        }
    }

    // MARK: At rest

    /// With no refresh under way the always-mounted overlay adds nothing: no busy
    /// indicator, spinner or page anchor; every element is named, the heading is a
    /// heading, the tool, heading and rows read top to bottom, and rows are 44 pt
    /// targets. A click in the top 44 pt strip (where the anchor lies when VoiceOver is
    /// on) still reaches the first row, so the overlay never steals a touch (#325).
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func restingOverlayAddsNothingAndPassesClicksThrough(_ typeSize: DynamicTypeSize) async throws {
        let hosted = try await Self.host(typeSize: typeSize)
        defer { hosted.close() }
        let nodes = hosted.elements()
        #expect(nodes.map(\.identifier) == Self.restingOrder, "\(Self.dump(nodes))")
        #expect(nodes.allSatisfy { !$0.spokenName.isEmpty }, "every element is named: \(Self.dump(nodes))")
        #expect(nodes.first { $0.identifier == Page.headingID }?.role == "AXHeading", "\(Self.dump(nodes))")
        let everything = ReloadGateAccessibilityTests.reachable(hosted.host)
        #expect(ReloadGateAccessibilityTests.busyIndicators(everything).isEmpty, "\(Self.dump(everything))")
        #expect(!everything.contains { $0.identifier.hasPrefix("fst.publication.") }, "\(Self.dump(everything))")
        Self.expectTargets(hosted, [Page.toolID] + (0..<Page.rowCount).map(Page.rowID), "\(typeSize) at rest")

        // Rows read top to bottom on screen too.
        let tops = try (0..<Page.rowCount).map {
            try #require(nativeHostedAccessibilityFrame(Page.rowID($0), in: hosted.host)).minY
        }
        #expect(tops == tops.sorted(), "rows read in visual order: \(tops)")

        // The boundary starts under the tool; its top 44 pt strip holds the heading and
        // the top of the first row.
        let tool = try #require(nativeHostedAccessibilityFrame(Page.toolID, in: hosted.host))
        let row = try #require(nativeHostedAccessibilityFrame(Page.rowID(0), in: hosted.host))
        let strip = tool.maxY + Page.minimumTarget
        #expect(row.minY < strip - 4, "the first row starts inside the anchor strip: \(row), strip ends \(strip)")
        hosted.window.orderFrontRegardless()
        let before = PublicationRefreshA11yPresses.shared.count[0, default: 0]
        nativeHostedClick(CGPoint(x: row.midX, y: (row.minY + min(row.maxY, strip)) / 2), in: hosted.host, window: hosted.window)
        try await nativeHostedSettle(hosted.host)
        #expect(PublicationRefreshA11yPresses.shared.count[0, default: 0] - before == 1,
                "a click at the top of the page reaches the first row")
    }

    // MARK: Rollover

    /// A new publication reads as one busy indicator named "Loading new scores" in place
    /// of the page: no stale heading or rows, no unnamed element, and the outside tool
    /// still first, named, a 44 pt target and pressable. After the reveal the spinner
    /// leaves the tree and the new publication's heading and rows read in order again.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func rolloverReadsOneNamedSpinnerThenNewRowsInOrder(_ typeSize: DynamicTypeSize) async throws {
        let hosted = try await Self.host(typeSize: typeSize, motion: .systemReduceMotion)
        defer { hosted.close() }
        try await hosted.session.observe(publicationId: 8)

        let refreshing = try await Self.waitForSpinner(hosted)
        #expect(refreshing.map(\.identifier) == [Page.toolID, Page.spinnerID], "\(Self.dump(refreshing))")
        let everything = ReloadGateAccessibilityTests.reachable(hosted.host)
        let busy = ReloadGateAccessibilityTests.busyIndicators(everything)
        #expect(busy.map(\.spokenName) == [Page.spinnerLabel], "one named busy indicator: \(Self.dump(everything))")
        #expect(ReloadGateAccessibilityTests.leaves(everything).allSatisfy { !$0.spokenName.isEmpty },
                "no unnamed element: \(Self.dump(everything))")
        Self.expectTargets(hosted, [Page.toolID], "\(typeSize) refreshing")
        let tool = try #require(nativeHostedAccessibilityElement(Page.toolID, in: hosted.host))
        #expect(tool.responds(to: NSSelectorFromString("accessibilityPerformPress")), "the tool stays pressable")

        try await Self.settleOnRows(hosted, publication: 8)
        let revealed = hosted.elements()
        #expect(revealed.map(\.identifier) == Self.restingOrder, "\(Self.dump(revealed))")
        #expect(ReloadGateAccessibilityTests.busyIndicators(ReloadGateAccessibilityTests.reachable(hosted.host)).isEmpty)
        Self.expectTargets(hosted, [Page.toolID] + (0..<Page.rowCount).map(Page.rowID), "\(typeSize) revealed")
    }

    // MARK: Text scaling

    /// Text inside the boundary takes the page's Dynamic Type size through the overlay
    /// layer: at AX5 a row's glyphs grow at least 1.35× and stay whole, before and after
    /// a rollover (HIG Accessibility: "offer text enlargement of at least 200%").
    ///
    /// The rollover runs Reduce Motion timing, not the hosted root's frozen fades: with
    /// `.instant` timing every wait is zero, and the hold and a `prepare`-less preparation
    /// both update in the pass that starts their tasks, after which SwiftUI never starts
    /// the spinner-out wait. Product boundaries always hold the spinner 400 ms, so this
    /// only affects frozen-fade hosts (load-transition, "Testing").
    @Test func rowTextGrowsWholeThroughTheBoundaryAtAX5() async throws {
        let item = (id: Page.rowID(0), text: "Song 1", style: ReloadGateA11yText.Style.body)
        let base: CGFloat
        do {
            let hosted = try await Self.host()
            defer { hosted.close() }
            let frame = try #require(nativeHostedAccessibilityFrame(item.id, in: hosted.host))
            base = try ReloadGateAccessibilityTests.inkHeight(hosted.host, in: frame)
        }
        let hosted = try await Self.host(typeSize: .accessibility5, motion: .systemReduceMotion)
        defer { hosted.close() }
        for context in ["before", "after"] {
            if context == "after" {
                try await hosted.session.observe(publicationId: 8)
                try await Self.settleOnRows(hosted, publication: 8)
            }
            let frame = try #require(nativeHostedAccessibilityFrame(item.id, in: hosted.host))
            let needed = ReloadGateAccessibilityTests.idealSize(item.text, item.style, .accessibility5)
            #expect(frame.height >= needed.height - 0.5, "\(context): the row is untruncated: \(frame) for \(needed)")
            let ink = try ReloadGateAccessibilityTests.inkHeight(hosted.host, in: frame)
            #expect(base >= 8 && ink > base * 1.35, "\(context): row glyphs grow at AX5: \(ink) pt from \(base) pt")
        }
    }

    // MARK: Reduce Motion

    /// With Reduce Motion (system or in-app) the rollover swaps without fades but keeps
    /// the spinner in the tree for its 400 ms minimum, so it never blinks; with motion
    /// the reveal also waits for the spinner fade (load-transition R3; HIG Accessibility:
    /// "When Reduce Motion is on, reduce automatic and repetitive animation"). A page
    /// whose `prepare` outlasts the hold (Songs re-reading its catalogue) reveals too, in
    /// either finishing order. Durations are lower bounds, so a slow runner cannot fail them.
    @Test(arguments: [Motion.systemReduceMotion, .appReduceMotion, .animated], [nil, Duration.milliseconds(900)])
    func rolloverHoldsTheSpinnerForItsMinimum(_ motion: Motion, prepareDelay: Duration?) async throws {
        let hosted = try await Self.host(motion: motion, prepareDelay: prepareDelay)
        defer { hosted.close() }
        let clock = ContinuousClock()
        let start = clock.now
        try await hosted.session.observe(publicationId: 8)
        let refreshing = try await Self.waitForSpinner(hosted)
        #expect(Self.spinners(refreshing).count == 1 && Self.rows(refreshing).isEmpty,
                "one spinner, no stale rows: \(Self.dump(refreshing))")
        try await Self.settleOnRows(hosted, publication: 8)
        let elapsed = clock.now - start
        let timing = PublicationRefreshTransition.Timing.standard(reduceMotion: motion != .animated)
        #expect(elapsed >= timing.minimumSpinner + timing.spinnerOut, "revealed after \(elapsed)")
    }
}
#endif
