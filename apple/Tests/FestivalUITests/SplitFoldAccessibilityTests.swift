#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Split fold accessibility (issue #346, backfilled by #482)

/// #346 made iPhone Duo's on-demand split (``OnDemandSplitStack``) keep its shape for the
/// fold's own update and push the open item in one column a run-loop turn later
/// (unfolding splits again), so folding with Song Detail's full leaderboard open no longer
/// leaves the outer display black. These hosted checks pin what VoiceOver gets through
/// that change, folding and unfolding twice, with and without Reduce Motion:
///
/// - **Split:** the list page reads before the open item, the item is read once, the
///   divider stays out of the tree and the window's Close names its Escape shortcut.
/// - **Fold, pending:** the open item stays readable in the fold's own update.
/// - **Folded:** only the open item is read (the covered list page leaves the tree), its
///   action keeps its name and at least its split-pane target on the outer display, and
///   the split's Close is gone (one column uses Back); the path is unchanged.
/// - **Unfolded:** the split order and Close come back for the same item.
///
/// The change adds no control or text, so target size is checked as the item's own
/// action surviving the move and text scaling is left to the Duo audit journeys (`DuoAX5`, shell group:
/// the split panes at AX5): macOS has no Dynamic Type (HIG Typography).
///
/// HIG designing-for-iphone-duo: "Preserve functionality, element state, hierarchy, and
/// access across displays/poses." HIG VoiceOver: "Specify how elements are grouped,
/// ordered or linked".
@MainActor
@Suite(.serialized)
struct SplitFoldAccessibilityTests {
    // MARK: - Fixture

    /// iPhone Duo inner display, landscape (regular width, vertical bar, fully open).
    static let inner = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))

    /// iPhone Duo outer display, portrait (compact width, folded).
    static let outer = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    ))

    nonisolated static let song = Song(
        songId: "fixture-song", title: "Fixture Anthem", artist: "The Fixtures", album: nil,
        year: 2024, durationSeconds: 180, albumArt: nil, difficulty: nil,
        pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
    )

    /// One split that #346 changed, with what its two pages expose.
    struct Scenario: CustomTestStringConvertible, Sendable {
        let name: String
        let section: FestivalSection
        let path: [AppRoute]
        /// The list page's first element, read first while split and gone while folded.
        let listMarker: String
        /// The open item's heading (no network: its offline state).
        let itemHeading: String
        /// The open item's action, checked for name and target size.
        let itemAction: String

        var testDescription: String { name }
    }

    nonisolated static let scenarios = [
        // The reported page: Song Detail beside its full Lead leaderboard.
        Scenario(
            name: "song-detail-leaderboard", section: .songs,
            path: [.songDetail(song), .songLeaderboard(song, .lead, 1)],
            listMarker: "Fixture Anthem, The Fixtures, 2024", itemHeading: "Leaderboard unavailable",
            itemAction: "Retry"
        ),
        // The same component on Rivals beside a rival.
        Scenario(
            name: "rivals-rival", section: .rivals,
            path: [.rivalDetail(rivalId: "fixture-rival", name: "Fixture Rival", scope: nil)],
            listMarker: "Fixture List Root", itemHeading: "No Player Selected", itemAction: "Choose Profile"
        ),
    ]

    /// The Duo pose the hosted split sees.
    @MainActor @Observable
    final class Pose {
        var folded = false
    }

    /// Records the section path the split writes.
    @MainActor
    final class PathRecorder {
        var path: [AppRoute] = []
    }

    /// The shell's tab-set deferral around one section's split, sized and laid out for
    /// the pose, as folding moves the app between the Duo's displays.
    struct Host: View {
        let session: FestivalSession
        let section: FestivalSection
        let pose: Pose
        @State var path: [AppRoute]
        let recorder: PathRecorder

        var body: some View {
            let size = pose.folded ? CGSize(width: 466, height: 678) : CGSize(width: 951, height: 669)
            FestivalShellContent(usesSidebarShell: false) { _, _ in
                OnDemandSplitStack(
                    section: section, session: session, visibleInstruments: Set(Instrument.allCases),
                    path: $path, isVisible: true
                ) { _ in
                    List { Text("Fixture List Root") }
                }
            }
            .environment(\.deviceLayout, pose.folded ? SplitFoldAccessibilityTests.outer : SplitFoldAccessibilityTests.inner)
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: path, initial: true) { _, new in recorder.path = new }
        }
    }

    /// A hosted split in a titled window whose toolbar carries the panes' items.
    @MainActor
    struct Hosted {
        let view: NSView
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.close()
            storage.removePersistentDomain(forName: suiteName)
        }

        /// The toolbar's item labels.
        var toolbarLabels: [String] { (window.toolbar?.items ?? []).map { $0.label } }
    }

    static let size = CGSize(width: 951, height: 678)
    static let budget: Duration = .seconds(60)

    /// Host a scenario's split on the inner display, toolbars bridged to the window.
    static func host(_ scenario: Scenario, pose: Pose, recorder: PathRecorder, reduceMotion: Bool) throws -> Hosted {
        nativeHostedEnableAccessibility()
        let suiteName = "fst-split-fold-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(reduceMotion, forKey: "fst.accessibility.reduceMotion")
        // No client: every page renders its offline state, with no network.
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let controller = NSHostingController(rootView: Host(
            session: session, section: scenario.section, pose: pose, path: scenario.path, recorder: recorder
        )
        .frame(width: size.width, height: size.height)
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark))
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), display: false)
        window.orderOut(nil)
        return Hosted(view: controller.view, window: window, storage: storage, suiteName: suiteName)
    }

    /// The elements VoiceOver reads, in navigation order.
    static func elements(_ hosted: Hosted) -> [MacAXNode] {
        hosted.view.layoutSubtreeIfNeeded()
        return macAccessibilityTree(hosted.view, navigationOrder: true).filter(\.isElement)
    }

    /// Wait until `ready` holds for the tree and the toolbar.
    static func settle(
        _ hosted: Hosted, _ what: String, sourceLocation: SourceLocation = #_sourceLocation,
        until ready: ([MacAXNode], [String]) -> Bool
    ) async throws {
        var budget = NativeHostedPollBudget(Self.budget)
        while !ready(elements(hosted), hosted.toolbarLabels), !budget.isExhausted {
            try await budget.sleep(for: .milliseconds(100))
        }
        let nodes = elements(hosted)
        #expect(
            ready(nodes, hosted.toolbarLabels),
            "\(what): toolbar \(hosted.toolbarLabels)\n\(nodes.map(\.description).joined(separator: "\n"))",
            sourceLocation: sourceLocation
        )
    }

    /// Resume after every main-queue block already enqueued has run: the split applies a
    /// window change in the next one (`DispatchQueue.main.async`).
    static func mainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: - Expectations

    /// The open item's action button: named, a button, and its frame.
    static func actionFrame(_ hosted: Hosted, _ scenario: Scenario, _ tree: String) throws -> CGRect {
        let action = try #require(
            nativeHostedAccessibilityElement(in: hosted.view) {
                nativeHostedAccessibilityString($0, "accessibilityRole") == "AXButton"
                    && nativeHostedAccessibilityString($0, "accessibilityLabel") == scenario.itemAction
            },
            "\(scenario.itemAction) button: \(tree)"
        )
        return try #require(nativeHostedAccessibilityFrame(of: action, in: hosted.view))
    }

    /// Split: the list page, then the open item read once; the divider stays out; one
    /// Close with its shortcut in the toolbar; nothing unnamed.
    ///
    /// - Returns: The open item's action frame in the trailing pane.
    @discardableResult
    static func expectSplit(
        _ hosted: Hosted, _ scenario: Scenario, _ phase: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> CGRect {
        let nodes = elements(hosted)
        macAccessibilityDump(nodes, name: "split-fold-\(scenario.name)-\(phase)")
        let tree = "\(phase)\n\(nodes.map(\.description).joined(separator: "\n"))"
        let list = try #require(nodes.firstIndex { $0.spokenName == scenario.listMarker }, "list page: \(tree)")
        let item = try #require(nodes.firstIndex { $0.spokenName == scenario.itemHeading }, "open item: \(tree)")
        #expect(list < item, "the list page reads before the open item: \(tree)", sourceLocation: sourceLocation)
        #expect(nodes[item].role == "AXHeading", "the open item's title is a heading: \(tree)", sourceLocation: sourceLocation)
        #expect(nodes.filter { $0.spokenName == scenario.itemHeading }.count == 1,
                "the open item is read once: \(tree)", sourceLocation: sourceLocation)
        #expect(!nodes.contains { $0.identifier == "fst.split.divider" }, "the divider is decorative", sourceLocation: sourceLocation)
        let items = hosted.window.toolbar?.items ?? []
        let close = items.filter { $0.label == "Close" }
        #expect(close.count == 1, "\(phase): one Close: \(hosted.toolbarLabels)", sourceLocation: sourceLocation)
        #expect(close.first?.toolTip == "Close (Esc)", "\(phase): Close names its shortcut", sourceLocation: sourceLocation)
        #expect(macAccessibilityFindings(nodes) == [], "\(phase)", sourceLocation: sourceLocation)
        let frame = try actionFrame(hosted, scenario, tree)
        #expect(frame.minX > inner.size.width / 2, "\(phase): \(scenario.itemAction) is in the trailing pane: \(frame)",
                sourceLocation: sourceLocation)
        return frame
    }

    /// Folded: one column with only the open item; its action keeps its name and at least
    /// the target it had in the split pane, on the outer display; no Close.
    static func expectFolded(
        _ hosted: Hosted, _ scenario: Scenario, _ phase: String, split: CGRect,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let nodes = elements(hosted)
        macAccessibilityDump(nodes, name: "split-fold-\(scenario.name)-\(phase)")
        let tree = "\(phase)\n\(nodes.map(\.description).joined(separator: "\n"))"
        #expect(nodes.filter { $0.spokenName == scenario.itemHeading && $0.role == "AXHeading" }.count == 1,
                "the open item's heading is read once: \(tree)", sourceLocation: sourceLocation)
        #expect(!nodes.contains { $0.spokenName == scenario.listMarker },
                "the covered list page leaves the tree: \(tree)", sourceLocation: sourceLocation)
        let identifiers = nativeHostedAccessibility(hosted.view).identifiers
        #expect(!identifiers.contains("fst.split.trailing"), "\(phase): no trailing pane", sourceLocation: sourceLocation)
        #expect(!hosted.toolbarLabels.contains("Close"), "\(phase): one column has no Close: \(hosted.toolbarLabels)",
                sourceLocation: sourceLocation)
        let frame = try actionFrame(hosted, scenario, tree)
        // The item gets the outer display's full width: its action never shrinks, and it
        // stays on screen. One point of tolerance for off-grid layout (accessibility.md).
        #expect(frame.width >= split.width - 1 && frame.height >= split.height - 1,
                "\(phase): \(scenario.itemAction) keeps its target: \(frame) vs split \(split)",
                sourceLocation: sourceLocation)
        #expect(frame.minX >= -0.5 && frame.maxX <= outer.size.width + 0.5,
                "\(phase): \(scenario.itemAction) is on the outer display: \(frame)", sourceLocation: sourceLocation)
        #expect(macAccessibilityFindings(nodes) == [], "\(phase)", sourceLocation: sourceLocation)
    }

    // MARK: - Fold and unfold

    /// Folding and unfolding twice keeps the open item readable on every frame, collapses
    /// the reading order to the item alone, and restores the split's order and Close.
    @Test(arguments: scenarios, [false, true])
    func foldingKeepsTheOpenItemReadable(_ scenario: Scenario, reduceMotion: Bool) async throws {
        let pose = Pose()
        let recorder = PathRecorder()
        let hosted = try Self.host(scenario, pose: pose, recorder: recorder, reduceMotion: reduceMotion)
        defer { hosted.close() }
        func ready(_ nodes: [MacAXNode], _ toolbar: [String], split: Bool) -> Bool {
            nodes.contains { $0.spokenName == scenario.itemHeading }
                && nodes.contains { $0.spokenName == scenario.itemAction }
                && nodes.contains { $0.spokenName == scenario.listMarker } == split
                && toolbar.contains("Close") == split
        }
        try await Self.settle(hosted, "split") { ready($0, $1, split: true) }
        let split = try Self.expectSplit(hosted, scenario, "split")

        for round in 1...2 {
            pose.folded = true
            // The fold's own update: the split keeps its shape, so the item is still read.
            let pending = Self.elements(hosted)
            #expect(pending.contains { $0.spokenName == scenario.itemHeading },
                    "round \(round): the open item stays readable while the fold applies")
            await Self.mainQueueTurn()
            try await Self.settle(hosted, "round \(round) folded") { ready($0, $1, split: false) }
            try Self.expectFolded(hosted, scenario, "\(round)-folded", split: split)
            #expect(recorder.path == scenario.path, "round \(round): folding keeps the open item")

            pose.folded = false
            await Self.mainQueueTurn()
            try await Self.settle(hosted, "round \(round) unfolded") { ready($0, $1, split: true) }
            try Self.expectSplit(hosted, scenario, "\(round)-unfolded")
            #expect(recorder.path == scenario.path, "round \(round): unfolding keeps the open item")
        }
    }
}
#endif
