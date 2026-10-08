#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Devices

/// One window the drawer floats in: its size, safe area, published layout and the
/// display corner radius the panel's concentric corners nest in.
struct DrawerCornerDevice: CustomTestStringConvertible, Sendable {
    let name: String
    let window: CGSize
    let safeArea: EdgeInsets
    let layout: DeviceLayout
    /// The display's corner radius (0 for a square-cornered display).
    let displayCorner: CGFloat

    var testDescription: String { name }

    /// The largest radius any panel corner can take here: concentric with the display
    /// corner at the drawer's margin (iOS 26+, never below the minimum) or the fixed
    /// pre-iOS 26 radius. The panel never sits closer to a display corner than the
    /// margin, so a corner nested further in only gets smaller.
    var worstPanelRadius: CGFloat {
        max(displayCorner - DrawerPlacement.margin, DrawerCorners.minimumRadius, DrawerCorners.legacyRadius)
    }

    /// The panel's frame, from the same placement the drawer resolves.
    var panelFrame: CGRect {
        let inner = CGSize(
            width: window.width - safeArea.leading - safeArea.trailing,
            height: window.height - safeArea.top - safeArea.bottom
        )
        return DrawerPlacement.resolve(size: inner, safeArea: safeArea, layout: layout).panelFrame(in: window)
    }

    /// The root's shell presentation for this layout (`FestivalRootView`).
    var presentation: ShellPresentation {
        ShellPresentation.resolve(layout: layout, usesSidebarShell: false)
    }

    /// Whether the root asks the footer to scroll at accessibility sizes (flyout or Duo).
    var footerScrolls: Bool {
        presentation.navigation == .flyout || layout.pose != .standard
    }

    private static func make(
        _ name: String, _ window: CGSize, _ safeArea: EdgeInsets, displayCorner: CGFloat,
        widthClass: WidthClass = .compact, heightClass: WidthClass = .regular,
        verticalBarEdge: HorizontalEdge? = nil, hinge: HingeState? = nil, occlusions: [CGRect] = []
    ) -> DrawerCornerDevice {
        DrawerCornerDevice(
            name: name, window: window, safeArea: safeArea,
            layout: DeviceLayout.resolve(LayoutSignals(
                size: window, widthClass: widthClass, heightClass: heightClass, safeAreaInsets: safeArea,
                verticalBarEdge: verticalBarEdge, hinge: hinge, occlusions: occlusions
            )),
            displayCorner: displayCorner
        )
    }

    /// The iPhones and iPhone Duo poses #17 made the corners concentric on. Display
    /// radii as measured in #17 (`FST_DEBUG_DRAWER_RADII`): ≈62 pt on iPhone 18 Pro,
    /// ≈47.3 pt on iPhone 13 geometry, 59 pt at the Duo outer display's outer corners.
    static let all: [DrawerCornerDevice] = [
        make("iPhone 18 Pro portrait", CGSize(width: 402, height: 874),
             EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), displayCorner: 62),
        make("iPhone 18 Pro landscape", CGSize(width: 874, height: 402),
             EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62), displayCorner: 62, heightClass: .compact),
        make("iPhone 13 portrait", CGSize(width: 390, height: 844),
             EdgeInsets(top: 47, leading: 0, bottom: 34, trailing: 0), displayCorner: 47.33),
        make("iPhone with Home button", CGSize(width: 375, height: 667),
             EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0), displayCorner: 0),
        make("Duo folded portrait", CGSize(width: 466, height: 678),
             EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84), displayCorner: 59,
             verticalBarEdge: .trailing, hinge: .closed, occlusions: [CGRect(x: 404, y: 8, width: 44, height: 36)]),
        make("Duo folded landscape", CGSize(width: 678, height: 466),
             EdgeInsets(top: 0, leading: 84, bottom: 21, trailing: 0), displayCorner: 59,
             verticalBarEdge: .leading, hinge: .closed, occlusions: [CGRect(x: 8, y: 18, width: 36, height: 44)]),
        make("Duo unfolded", CGSize(width: 951, height: 669),
             EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84), displayCorner: 59,
             widthClass: .regular, verticalBarEdge: .trailing, hinge: .fullyOpen),
    ]
}

// MARK: - Hosting

private let drawerIDPrefix = "fst.shell.drawer."

/// A session with no network access, optionally with a stored selected player.
@MainActor
private func drawerCornerSession(player: Bool) -> FestivalSession {
    guard player else { return FestivalSession(factory: { throw FestivalAPIError.invalidResource }) }
    let defaults = UserDefaults(suiteName: "fst.tests.drawer-corners.\(UUID().uuidString)")!
    defaults.set(
        Data(#"{"accountId":"fixture-1","displayName":"Fixture Player"}"#.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    return FestivalSession(factory: { throw FestivalAPIError.invalidResource }, selectionStorage: defaults)
}

/// The drawer as the root mounts it on `device`, hosted in a window of the device's size
/// with its safe area, open and settled.
@MainActor
private func hostDrawer(
    on device: DrawerCornerDevice, player: Bool, typeSize: DynamicTypeSize, reduceTransparency: Bool = true
) async throws -> (host: NSView, window: NSWindow) {
    let session = drawerCornerSession(player: player)
    let presentation = device.presentation
    let host = nativeHostedView(
        FestivalDrawer(
            session: session, visibleSections: presentation.sections(profile: player ? .player : .none),
            hideShop: false, showsSearch: presentation.navigation == .flyout,
            closesOnEscape: device.footerScrolls, footerScrollsAtAccessibilitySizes: device.footerScrolls,
            onIntent: { _ in }, onClose: {}
        )
        .safeAreaPadding(device.safeArea)
        .environment(\.deviceLayout, device.layout)
        .environment(\.dynamicTypeSize, typeSize)
        .frame(width: device.window.width, height: device.window.height)
        .preferredColorScheme(.dark),
        size: device.window, forceGlassFallback: reduceTransparency
    )
    let window = nativeHostedWindow(host, size: device.window)
    _ = try await nativeHostedSettle(host, untilText: ["Festival Score Tracker", "Settings"])
    return (host, window)
}

/// The drawer's identifiers in reading order: Search (flyout), the destinations, the
/// profile footer, then Settings.
private func expectedDrawerIDs(on device: DrawerCornerDevice, player: Bool) -> [String] {
    let presentation = device.presentation
    let profile: FestivalProfileKind = player ? .player : .none
    let rows = (presentation.navigation == .flyout ? [DrawerMenu.search] : []) + DrawerMenu.browse(
        profile: profile, visibleSections: presentation.sections(profile: profile), hideShop: false
    )
    let footer = player ? ["view-profile", "deselect-profile"] : ["select-profile"]
    return ["close"] + rows.map(\.id) + footer + DrawerMenu.more.map(\.id)
}

// MARK: - Corner geometry

/// Points of `shape` (sampled every point within 24 pt of `frame`'s edges) that fall
/// outside `panel`: an element the panel's rounded corners would clip.
private func clippedPoints(of shape: Path, in frame: CGRect, panel: Path) -> [CGPoint] {
    var misses: [CGPoint] = []
    var y = frame.minY + 0.5
    while y < frame.maxY {
        var x = frame.minX + 0.5
        while x < frame.maxX {
            let point = CGPoint(x: x, y: y)
            let edgeDistance = min(x - frame.minX, frame.maxX - x, y - frame.minY, frame.maxY - y)
            if edgeDistance <= 24, shape.contains(point), !panel.contains(point) {
                misses.append(point)
            }
            x += 1
        }
        y += 1
    }
    return misses
}

/// The drawn target of a drawer element: the close button's circle, the heading's text
/// box, the bordered Deselect button, or a row's rounded highlight.
private func drawnShape(of id: String, in frame: CGRect) -> Path {
    switch id {
    case "close": Circle().path(in: frame)
    case "heading": Rectangle().path(in: frame)
    case "deselect-profile": Capsule().path(in: frame)
    default: RoundedRectangle(cornerRadius: DrawerCorners.rowRadius, style: .continuous).path(in: frame)
    }
}

// MARK: - Tests

/// Accessibility of the navigation drawer's concentric corners (#396, for #17).
///
/// #17 made the drawer panel's corners follow each device's display corners
/// (`ConcentricRectangle`, up to ≈54 pt on iPhone 18 Pro instead of the fixed 44 pt),
/// clipping the panel's contents and the scrim cut-out to that shape. These hosted tests
/// run in `apple-ci` and pin what that change must not cost assistive technologies, on
/// every iPhone and iPhone Duo geometry #17 targets, anonymous and with a player, at the
/// default and the largest accessibility text size (the layout branches; real glyph
/// growth is checked by `DrawerAccessibilityJourneyTests` on the iPhone simulator):
///
/// - the panel reads heading, Close, rows, profile footer, Settings, in drawn order, each
///   control a named button, only the current page selected, no symbol exposed;
/// - each control keeps a 44 pt target (HIG Accessibility, Mobility: "Strive for the
///   platform's recommended minimum control size", 44x44 pt on iOS);
/// - no control or the heading is cut by the corners at the largest radius the panel can
///   take there, so nothing VoiceOver reads or a finger targets is clipped away.
@MainActor
@Suite struct DrawerCornersAccessibilityTests {
    /// Reading order, names, roles and state, target size and corner clearance.
    @Test(arguments: DrawerCornerDevice.all, [DynamicTypeSize.large, .accessibility5])
    func drawerReadsInOrderAndClearsItsConcentricCorners(
        device: DrawerCornerDevice, typeSize: DynamicTypeSize
    ) async throws {
        for player in [false, true] {
            try await assertDrawer(on: device, player: player, typeSize: typeSize)
        }
    }

    /// Reduce Transparency swaps the glass for its opaque fallback in the same concentric
    /// shape; the accessibility tree does not change.
    @Test func drawerTreeIsTheSameWithReduceTransparency() async throws {
        let device = DrawerCornerDevice.all[0]
        var trees: [[String]] = []
        for reduce in [true, false] {
            let (host, window) = try await hostDrawer(on: device, player: true, typeSize: .large,
                                                      reduceTransparency: reduce)
            defer { window.orderOut(nil) }
            trees.append(macAccessibilityTree(host).filter(\.isElement).map(\.description))
        }
        #expect(trees[0] == trees[1])
    }

    /// The containment check itself: a target in the panel's corner square is reported.
    @Test func clippedPointsFindsATargetInTheCorner() {
        let panel = CGRect(x: 8, y: 8, width: 330, height: 850)
        let shape = RoundedRectangle(cornerRadius: 54, style: .continuous).path(in: panel)
        let corner = CGRect(x: panel.minX, y: panel.minY, width: 44, height: 44)
        #expect(!clippedPoints(of: Rectangle().path(in: corner), in: corner, panel: shape).isEmpty)
        let inside = corner.offsetBy(dx: 40, dy: 40)
        #expect(clippedPoints(of: Circle().path(in: inside), in: inside, panel: shape).isEmpty)
    }

    private func assertDrawer(on device: DrawerCornerDevice, player: Bool, typeSize: DynamicTypeSize) async throws {
        let (host, window) = try await hostDrawer(on: device, player: player, typeSize: typeSize)
        defer { window.orderOut(nil) }
        let context = "\(device.name), \(player ? "player" : "anonymous"), \(typeSize)"
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "drawer-corners-\(device.name)-\(player)-\(typeSize)")

        // Names, roles, state and reading order.
        let elements = nodes.filter(\.isElement)
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(context): \(macAccessibilityFindings(nodes))")
        #expect(!elements.contains { $0.role == "AXImage" }, "\(context): symbols stay decorative")
        let heading = try #require(elements.first { $0.role == "AXHeading" }, "\(context): no heading")
        #expect(heading.spokenName == "Festival Score Tracker")
        let controls = elements.filter { $0.identifier.hasPrefix(drawerIDPrefix) }
        let ids = controls.map { String($0.identifier.dropFirst(drawerIDPrefix.count)) }
        #expect(ids == expectedDrawerIDs(on: device, player: player), "\(context): reading order")
        let containers: Set<String> = ["AXGroup", "AXScrollArea", "AXScrollBar"]
        #expect(elements.first { !containers.contains($0.role) }?.role == "AXHeading",
                "\(context): the heading reads first")
        #expect(controls.allSatisfy { $0.role == "AXButton" }, "\(context): \(controls)")
        #expect(controls.allSatisfy { !$0.spokenName.isEmpty }, "\(context): \(controls)")
        #expect(controls.first?.spokenName == "Close Navigation")
        #expect(controls.filter(\.selected).map(\.identifier) == [drawerIDPrefix + "songs"],
                "\(context): only the current page is selected")
        if player {
            #expect(controls.contains { $0.spokenName == "Fixture Player, Selected Player" })
            #expect(controls.contains { $0.spokenName == "Deselect Profile" })
        }

        // Frames: the measured layout sits in the panel the placement resolves.
        let panel = device.panelFrame
        let frames = try ids.map { id in
            (id, try #require(nativeHostedAccessibilityFrame(drawerIDPrefix + id, in: host), "\(context): \(id)"))
        }
        let close = try #require(frames.first { $0.0 == "close" }?.1)
        #expect(abs(close.maxX - (panel.maxX - DrawerCorners.contentInset)) < 1, "\(context): \(close) in \(panel)")
        let firstRow = try #require(frames.dropFirst().first?.1)
        #expect(abs(firstRow.minX - (panel.minX + DrawerCorners.contentInset)) < 1,
                "\(context): \(firstRow) in \(panel)")
        let headingFrame = try #require(
            nativeHostedAccessibilityElement(in: host) {
                nativeHostedAccessibilityString($0, "accessibilityRole") == "AXHeading"
            }.flatMap { nativeHostedAccessibilityFrame(of: $0, in: host) }
        )

        // Targets: 44 pt or more. macOS draws the large bordered Deselect at its own 28 pt
        // control size; `DrawerAccessibilityJourneyTests` measures it on iPhone (≥ 44 pt).
        for (id, frame) in frames where id != "deselect-profile" {
            #expect(frame.width >= 44 && frame.height >= 44, "\(context): \(id) target \(frame)")
        }

        // Corners: the heading, Close and a pinned footer never leave the panel; nothing
        // inside the panel is cut by its corners at their largest radius.
        let pinned = ["close"] + (device.footerScrolls && typeSize.isAccessibilitySize ? [] :
            Array(ids.suffix(player ? 3 : 2)))
        let tolerance = panel.insetBy(dx: -0.5, dy: -0.5)
        #expect(tolerance.contains(headingFrame), "\(context): heading \(headingFrame) in \(panel)")
        for (id, frame) in frames where pinned.contains(id) {
            #expect(tolerance.contains(frame), "\(context): \(id) \(frame) in \(panel)")
        }
        let panelShape = RoundedRectangle(cornerRadius: device.worstPanelRadius, style: .continuous).path(in: panel)
        for (id, frame) in frames + [("heading", headingFrame)] where tolerance.contains(frame) {
            let clipped = clippedPoints(of: drawnShape(of: id, in: frame), in: frame, panel: panelShape)
            let radius = device.worstPanelRadius
            #expect(clipped.isEmpty, "\(context): \(id) \(frame) clipped by the \(radius) pt corner of \(panel) at \(clipped.prefix(3))")
        }
    }
}
#endif
