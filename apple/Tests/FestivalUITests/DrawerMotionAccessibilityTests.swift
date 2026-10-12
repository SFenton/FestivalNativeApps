#if os(macOS)
import AppKit
import Observation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Shells

/// One shell the drawer opens in: a window from `DrawerCornerDevice` and the presentation
/// the root resolves there (the iPad's regular width is the flyout shell).
struct DrawerMotionShell: CustomTestStringConvertible, Sendable {
    let device: DrawerCornerDevice
    let presentation: ShellPresentation

    var testDescription: String { device.name }

    /// Whether the root asks the footer to scroll at accessibility sizes (flyout or Duo).
    var footerScrolls: Bool {
        presentation.navigation == .flyout || device.layout.pose != .standard
    }

    /// iPad Pro 11-inch portrait at full width: the overlay flyout (`ShellPresentation`
    /// `.flyout`), with its Search row.
    static let iPad: DrawerMotionShell = {
        let window = CGSize(width: 834, height: 1210)
        let safeArea = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        let layout = DeviceLayout.resolve(LayoutSignals(
            size: window, widthClass: .regular, heightClass: .regular, safeAreaInsets: safeArea
        ))
        let device = DrawerCornerDevice(
            name: "iPad Pro 11-inch portrait", window: window, safeArea: safeArea, layout: layout, displayCorner: 18
        )
        return DrawerMotionShell(
            device: device,
            presentation: ShellPresentation.resolve(layout: layout, usesSidebarShell: true, persistentSidebar: false)
        )
    }()

    /// Every iPhone and iPhone Duo window `DrawerCornersAccessibilityTests` covers, then
    /// the iPad flyout.
    static let all: [DrawerMotionShell] = DrawerCornerDevice.all.map {
        DrawerMotionShell(device: $0, presentation: $0.presentation)
    } + [iPad]

    /// iPhone 18 Pro portrait, the tab shell.
    static var iPhone: DrawerMotionShell { all[0] }

    /// iPhone Duo folded portrait, beside the system vertical bar.
    static var duoFolded: DrawerMotionShell {
        all.first { $0.device.name == "Duo folded portrait" }!
    }
}

// MARK: - Harness

/// What the root does with the drawer (`FestivalRootView`): presents it, closes it, and
/// unmounts it on `onDismissed`. The harness keeps it mounted so a test can read the
/// closing drawer for as long as it needs.
@MainActor
@Observable
private final class DrawerMotionModel {
    var presented: Bool
    /// `onClose` calls: the scrim, the close button or Escape asked to close.
    var closeRequests = 0
    /// `onDismissed` calls: a close sequence finished.
    var dismissals = 0
    /// Clicks that reached the page's button under the drawer.
    var pageTaps = 0

    init(presented: Bool) {
        self.presented = presented
    }
}

private let pageActionID = "fst.test.drawer-motion.page-action"
private let drawerIDPrefix = "fst.shell.drawer."
/// The page button: 44 pt wide, so it fits in the strip the phone panels leave uncovered.
private let pageActionSize = CGSize(width: 44, height: 88)

/// A page button in the top trailing corner, outside the panel, under the drawer as the
/// root stacks it.
private struct DrawerMotionHarness: View {
    let model: DrawerMotionModel
    let session: FestivalSession
    let shell: DrawerMotionShell
    let player: Bool
    let animatesIn: Bool
    let slides: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button("Page Action") { model.pageTaps += 1 }
                .buttonStyle(.plain)
                .frame(width: pageActionSize.width, height: pageActionSize.height)
                .contentShape(Rectangle())
                .accessibilityIdentifier(pageActionID)
                .padding(.top, 16)
            FestivalDrawer(
                session: session,
                visibleSections: shell.presentation.sections(profile: player ? .player : .none),
                hideShop: false, showsSearch: shell.presentation.navigation == .flyout,
                closesOnEscape: shell.footerScrolls, footerScrollsAtAccessibilitySizes: shell.footerScrolls,
                isPresented: model.presented, animatesIn: animatesIn, slides: slides,
                onIntent: { _ in }, onClose: { model.closeRequests += 1 },
                onDismissed: { model.dismissals += 1 }
            )
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .safeAreaPadding(shell.device.safeArea)
    }
}

/// A session with no network access, optionally with a stored selected player.
@MainActor
private func drawerMotionSession(player: Bool) -> FestivalSession {
    guard player else { return FestivalSession(factory: { throw FestivalAPIError.invalidResource }) }
    let defaults = UserDefaults(suiteName: "fst.tests.drawer-motion.\(UUID().uuidString)")!
    defaults.set(
        Data(#"{"accountId":"fixture-1","displayName":"Fixture Player"}"#.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    return FestivalSession(factory: { throw FestivalAPIError.invalidResource }, selectionStorage: defaults)
}

/// One hosted drawer and its model.
@MainActor
private struct HostedDrawer {
    let host: NSHostingView<NativeHostedRoot<AnyView>>
    let window: NSWindow
    let model: DrawerMotionModel

    /// The drawer's identified controls, in tree order.
    var controlIDs: [String] {
        macAccessibilityTree(host).filter { $0.isElement && $0.identifier.hasPrefix(drawerIDPrefix) }
            .map { String($0.identifier.dropFirst(drawerIDPrefix.count)) }
    }

    /// Every element assistive technologies read.
    var elements: [MacAXNode] { macAccessibilityTree(host).filter(\.isElement) }

    /// Frames of the drawer's identified controls.
    func frames(_ ids: [String]) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            nativeHostedAccessibilityFrame(drawerIDPrefix + id, in: host).map { (id, $0) }
        })
    }

    /// Wait until `ready` holds (a recorded issue when it never does).
    func settle(
        _ timeout: Duration = .seconds(20), animationGrace: Duration = .seconds(1),
        sourceLocation: SourceLocation = #_sourceLocation, until ready: @MainActor () -> Bool
    ) async throws {
        _ = try await nativeHostedSettle(
            host, timeout: timeout, animationGrace: animationGrace, sourceLocation: sourceLocation, until: ready
        )
    }
}

/// Host the drawer over a page button in `shell`'s window.
@MainActor
private func hostDrawer(
    _ shell: DrawerMotionShell, player: Bool = true, typeSize: DynamicTypeSize = .large,
    animatesIn: Bool, slides: Bool, ordered: Bool = false
) async throws -> HostedDrawer {
    let model = DrawerMotionModel(presented: true)
    let size = shell.device.window
    let host = nativeHostedView(
        AnyView(
            DrawerMotionHarness(
                model: model, session: drawerMotionSession(player: player), shell: shell,
                player: player, animatesIn: animatesIn, slides: slides
            )
            .environment(\.deviceLayout, shell.device.layout)
            .environment(\.dynamicTypeSize, typeSize)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
        ),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    // Still 10,000 pt off screen; AppKit delivers clicks only to an ordered-in window.
    if ordered { window.orderFrontRegardless() }
    let hosted = HostedDrawer(host: host, window: window, model: model)
    _ = try await nativeHostedSettle(host, untilText: ["Festival Score Tracker", "Settings"])
    return hosted
}

/// The drawer's identifiers in reading order: Close, Search (flyout), the destinations,
/// the profile footer, then Settings.
private func expectedDrawerIDs(_ shell: DrawerMotionShell, player: Bool) -> [String] {
    let profile: FestivalProfileKind = player ? .player : .none
    let rows = (shell.presentation.navigation == .flyout ? [DrawerMenu.search] : []) + DrawerMenu.browse(
        profile: profile, visibleSections: shell.presentation.sections(profile: profile), hideShop: false
    )
    let footer = player ? ["view-profile", "deselect-profile"] : ["select-profile"]
    return ["close"] + rows.map(\.id) + footer + DrawerMenu.more.map(\.id)
}

/// Where the harness puts the page button, in top-left host coordinates.
private func pageActionFrame(_ shell: DrawerMotionShell) -> CGRect {
    let device = shell.device
    return CGRect(
        origin: CGPoint(x: device.window.width - device.safeArea.trailing - pageActionSize.width,
                        y: device.safeArea.top + 16),
        size: pageActionSize
    )
}

/// Whether two frames match within half a point.
private func sameFrame(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
    guard let lhs, let rhs else { return false }
    return abs(lhs.minX - rhs.minX) < 0.5 && abs(lhs.minY - rhs.minY) < 0.5
        && abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
}

// MARK: - Tests

/// Accessibility of the drawer's open and close sequence (#489, for #362).
///
/// #362 made the drawer fade its scrim in place, then slide the panel in, and run the same
/// sequence back on close; the drawer stays mounted but hidden and untouchable until the
/// scrim has faded, and with Reduce Motion the panel fades in place instead of sliding
/// (HIG Accessibility: "Replace motion transitions with fades where appropriate"). The
/// static drawer's names, order and targets are `DrawerCornersAccessibilityTests`; these
/// pin what the sequence must not cost on every iPhone, iPhone Duo and iPad shell:
///
/// - after the animated open, sliding or fading, the drawer reads exactly as the static
///   drawer does, every control at its resting frame (44 pt targets inside the panel);
/// - from the moment it starts closing, VoiceOver no longer reads the drawer and clicks
///   reach the page under it, and reopening mid-close brings it back whole;
/// - with Reduce Motion the panel's controls never leave their resting frames, so the
///   VoiceOver cursor and Switch Control highlight never travel with a slide.
///
/// `DrawerAccessibilityJourneyTests` audits the same states on the iPhone simulator.
@MainActor
@Suite struct DrawerMotionAccessibilityTests {
    /// After the animated open (slide, or the Reduce Motion fade) the tree and every
    /// control's frame match the static open drawer's.
    @Test(arguments: DrawerMotionShell.all, [true, false])
    func animatedOpenRestsAsTheStaticDrawer(shell: DrawerMotionShell, slides: Bool) async throws {
        try await assertAnimatedOpen(shell, typeSize: .large, slides: slides)
    }

    /// The same at the largest accessibility text size, where the iPad and Duo footers
    /// scroll with the rows.
    @Test(arguments: [DrawerMotionShell.iPhone, .duoFolded, .iPad], [true, false])
    func animatedOpenRestsAsTheStaticDrawerAtAX5(shell: DrawerMotionShell, slides: Bool) async throws {
        try await assertAnimatedOpen(shell, typeSize: .accessibility5, slides: slides)
    }

    /// Closing hides the drawer from assistive technologies and passes clicks to the page
    /// at once, before its sequence ends; the sequence then reports one dismissal, and
    /// reopening restores the whole drawer.
    @Test(arguments: [DrawerMotionShell.iPhone, .duoFolded, .iPad], [true, false])
    func closingDrawerHandsThePageBackAtOnce(shell: DrawerMotionShell, slides: Bool) async throws {
        let context = "\(shell.device.name), \(slides ? "slide" : "Reduce Motion")"
        let drawer = try await hostDrawer(shell, animatesIn: true, slides: slides, ordered: true)
        defer { drawer.window.orderOut(nil) }
        let expected = expectedDrawerIDs(shell, player: true)
        try await drawer.settle { drawer.controlIDs == expected }
        let openTree = drawer.elements.map(\.description)
        #expect(!drawer.elements.contains { $0.identifier == pageActionID },
                "\(context): the open drawer is modal; VoiceOver reads only the drawer")
        let page = pageActionFrame(shell)
        let panel = shell.device.panelFrame
        #expect(!page.intersects(panel), "\(context): the page button \(page) sits beside the panel \(panel)")
        let tap = CGPoint(x: page.midX, y: page.midY)

        // Open: the click lands on the scrim, which asks to close; the page gets nothing.
        nativeHostedClick(tap, in: drawer.host, window: drawer.window)
        try await drawer.settle { drawer.model.closeRequests == 1 }
        #expect(drawer.model.pageTaps == 0, "\(context): the open drawer's scrim covers the page")

        // Closing: hidden and untouchable from the first frame, not after the sequence.
        drawer.model.presented = false
        drawer.host.layoutSubtreeIfNeeded()
        let closing = drawer.elements
        #expect(!closing.contains { $0.identifier.hasPrefix(drawerIDPrefix) || $0.role == "AXHeading" },
                "\(context): VoiceOver still reads the closing drawer: \(closing.map(\.description))")
        #expect(closing.contains { $0.identifier == pageActionID }, "\(context): the page is readable")
        #expect(sameFrame(nativeHostedAccessibilityFrame(pageActionID, in: drawer.host), page), "\(context): page frame")
        nativeHostedClick(tap, in: drawer.host, window: drawer.window)
        try await drawer.settle { drawer.model.pageTaps == 1 }
        #expect(drawer.model.closeRequests == 1, "\(context): the closing drawer took the click")

        // The sequence finishes once, and the drawer stays out of the tree.
        try await drawer.settle { drawer.model.dismissals >= 1 }
        #expect(drawer.model.dismissals == 1, "\(context)")
        #expect(drawer.controlIDs.isEmpty, "\(context): \(drawer.controlIDs)")

        // Reopening: the whole drawer, in order, at rest.
        drawer.model.presented = true
        try await drawer.settle { drawer.elements.map(\.description) == openTree }
        #expect(drawer.elements.map(\.description) == openTree, "\(context): reopened tree")
    }

    /// Reopening before the close sequence ends returns the drawer whole and at rest.
    @Test(arguments: [true, false])
    func reopeningMidCloseRestoresTheDrawer(slides: Bool) async throws {
        let shell = DrawerMotionShell.iPhone
        let expected = expectedDrawerIDs(shell, player: true)
        let resting = try await hostDrawer(shell, animatesIn: false, slides: slides)
        try await resting.settle { resting.controlIDs == expected }
        let restingFrames = resting.frames(expected)
        let openTree = resting.elements.map(\.description)
        resting.window.orderOut(nil)

        let drawer = try await hostDrawer(shell, animatesIn: true, slides: slides)
        defer { drawer.window.orderOut(nil) }
        try await drawer.settle {
            drawer.controlIDs == expected
                && expected.allSatisfy { sameFrame(drawer.frames([$0])[$0], restingFrames[$0]) }
        }

        drawer.model.presented = false
        drawer.host.layoutSubtreeIfNeeded()
        #expect(drawer.controlIDs.isEmpty, "closing hides the drawer")
        drawer.model.presented = true
        try await drawer.settle {
            drawer.elements.map(\.description) == openTree
                && expected.allSatisfy { sameFrame(drawer.frames([$0])[$0], restingFrames[$0]) }
        }
        #expect(drawer.elements.map(\.description) == openTree)
        for id in expected {
            #expect(sameFrame(drawer.frames([id])[id], restingFrames[id]), "\(id) returns to rest")
        }
    }

    /// The panel stage the drawer applies, rendered at every point of the sequence: with
    /// Reduce Motion a control's accessibility frame never moves; when sliding it follows
    /// `DrawerMotion` and comes to rest only at the end.
    @Test(arguments: [true, false])
    func panelStageKeepsReduceMotionControlsAtRest(slides: Bool) async throws {
        let model = PanelStageModel()
        let size = CGSize(width: 402, height: 200)
        let hidden: CGFloat = 360
        let host = nativeHostedView(
            PanelStageHarness(model: model, slides: slides, hiddenDistance: hidden)
                .frame(width: size.width, height: size.height),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host) { nativeHostedAccessibilityFrame(panelStageID, in: host) != nil }
        let rest = try #require(nativeHostedAccessibilityFrame(panelStageID, in: host))

        var readable = 0
        for step in 0...20 {
            let presence = Double(step) / 20
            let motion = DrawerMotion(presence: presence, slides: slides)
            model.presence = presence
            try await nativeHostedSettle(host)
            guard let frame = nativeHostedAccessibilityFrame(panelStageID, in: host) else {
                // Only a fully transparent panel (the Reduce Motion fade's start) may drop out.
                #expect(motion.panelOpacity == 0, "presence \(presence): the visible panel left the tree")
                continue
            }
            readable += 1
            let expected = rest.offsetBy(dx: motion.panelOffset(hiddenDistance: hidden), dy: 0)
            #expect(sameFrame(frame, expected), "presence \(presence): \(frame), expected \(expected)")
            if !slides { #expect(sameFrame(frame, rest), "presence \(presence): Reduce Motion moved the control") }
        }
        #expect(readable >= 10, "the control stays readable through most of the sequence")
    }

    // MARK: Helpers

    private func assertAnimatedOpen(_ shell: DrawerMotionShell, typeSize: DynamicTypeSize, slides: Bool) async throws {
        let context = "\(shell.device.name), \(typeSize), \(slides ? "slide" : "Reduce Motion")"
        let expected = expectedDrawerIDs(shell, player: true)
        let still = try await hostDrawer(shell, typeSize: typeSize, animatesIn: false, slides: slides)
        defer { still.window.orderOut(nil) }
        try await still.settle { still.controlIDs == expected }
        let stillTree = still.elements.map(\.description)
        let stillFrames = still.frames(expected)

        let animated = try await hostDrawer(shell, typeSize: typeSize, animatesIn: true, slides: slides)
        defer { animated.window.orderOut(nil) }
        try await animated.settle {
            animated.controlIDs == expected
                && expected.allSatisfy { sameFrame(animated.frames([$0])[$0], stillFrames[$0]) }
        }
        #expect(animated.controlIDs == expected, "\(context): reading order")
        #expect(animated.elements.map(\.description) == stillTree, "\(context): names, roles and state")
        let frames = animated.frames(expected)
        let panel = shell.device.panelFrame.insetBy(dx: -0.5, dy: -0.5)
        for id in expected {
            let frame = try #require(frames[id], "\(context): \(id) has no frame")
            #expect(sameFrame(frame, stillFrames[id]), "\(context): \(id) at \(frame), resting \(String(describing: stillFrames[id]))")
            #expect(frame.minX >= panel.minX && frame.maxX <= panel.maxX, "\(context): \(id) \(frame) in \(panel)")
            // macOS draws the bordered Deselect at its own control size; the iPhone journey
            // measures it at 44 pt.
            if id != "deselect-profile" {
                #expect(frame.width >= 44 && frame.height >= 44, "\(context): \(id) target \(frame)")
            }
        }
    }
}

// MARK: - Panel stage harness

private let panelStageID = "fst.test.drawer-motion.stage"

@MainActor
@Observable
private final class PanelStageModel {
    var presence: Double = 1
}

/// A 44 pt control laid out where a panel's close button rests, moved by
/// ``DrawerPanelStage`` at the model's presence.
private struct PanelStageHarness: View {
    let model: PanelStageModel
    let slides: Bool
    let hiddenDistance: CGFloat

    var body: some View {
        Button("Close Navigation") {}
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityIdentifier(panelStageID)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 296)
            .modifier(DrawerPanelStage(
                presence: model.presence, slides: slides, hiddenDistance: hiddenDistance, dragOffset: 0
            ))
    }
}
#endif
