import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Layout fixtures

/// Representative layouts (points) for the shell policy. Geometry mirrors
/// `DeviceLayoutTests`; the insets are illustrative, not asserted device truth.
private enum Layouts {
    static let iPhonePortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 402, height: 874), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
    ))
    /// A large iPhone in landscape reports regular width but has no hinge or vertical bar.
    static let largeIPhoneLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 956, height: 440), widthClass: .regular, heightClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
    ))
    static let duoFoldedPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed,
        occlusions: [CGRect(x: 404, y: 8, width: 44, height: 36)]
    ))
    /// Upside down: bar and camera on the leading edge, camera bottom-left.
    static let duoFoldedUpsideDown = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 34, leading: 84, bottom: 0, trailing: 0),
        verticalBarEdge: .leading, hinge: .closed,
        occlusions: [CGRect(x: 18, y: 634, width: 44, height: 36)]
    ))
    /// Landscape with the camera top-left: bar leading.
    static let duoFoldedLandscapeLeading = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 678, height: 466), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 84, bottom: 21, trailing: 0),
        verticalBarEdge: .leading, hinge: .closed,
        occlusions: [CGRect(x: 8, y: 18, width: 36, height: 44)]
    ))
    /// Landscape with the camera bottom-right: bar trailing.
    static let duoFoldedLandscapeTrailing = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 678, height: 466), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 21, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed,
        occlusions: [CGRect(x: 634, y: 404, width: 36, height: 44)]
    ))
    static let duoUnfolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    static let duoPartiallyFolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .partiallyOpen,
        divisions: [CGRect(x: 455, y: 0, width: 41, height: 669)]
    ))
    static let duoUnfoldedPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
    ))

    /// Every folded outer rotation.
    static let foldedRotations = [
        duoFoldedPortrait, duoFoldedUpsideDown, duoFoldedLandscapeLeading, duoFoldedLandscapeTrailing,
    ]
}

// MARK: - Section set and navigation

/// iPhone portrait keeps tabs and the drawer; Statistics leaves the bar for the Search
/// tab (issue #92).
@Test func iPhoneKeepsCompactTabs() {
    let presentation = ShellPresentation.resolve(layout: Layouts.iPhonePortrait, usesSidebarShell: false)
    #expect(presentation == ShellPresentation(navigation: .tabs, usesRegularSectionSet: false))
    #expect(presentation.usesDrawer)
    #expect(presentation.sections(profile: .player)
        == [.songs, .suggestions, .compete, .settings])
}

/// Operator 2026-09-28: large iPhones in landscape keep their portrait tabs.
@Test func largeIPhoneLandscapeKeepsPortraitTabs() {
    #expect(!Layouts.largeIPhoneLandscape.usesRegularSectionSet)
    let presentation = ShellPresentation.resolve(
        layout: Layouts.largeIPhoneLandscape, usesSidebarShell: false
    )
    #expect(presentation.sections(profile: .player)
        == [.songs, .suggestions, .compete, .settings])
}

/// The folded Duo is compact in every rotation: Compete, tabs, drawer.
@Test(arguments: Layouts.foldedRotations)
func duoFoldedKeepsCompactTabs(layout: DeviceLayout) {
    let presentation = ShellPresentation.resolve(layout: layout, usesSidebarShell: false)
    #expect(presentation == ShellPresentation(navigation: .tabs, usesRegularSectionSet: false))
}

/// The Duo inner display (flat, partially folded, or portrait) splits Compete into
/// Leaderboards and Rivals while keeping the tab shell for continuity with folded.
@Test(arguments: [Layouts.duoUnfolded, Layouts.duoPartiallyFolded, Layouts.duoUnfoldedPortrait])
func duoInnerDisplayUsesRegularSections(layout: DeviceLayout) {
    let presentation = ShellPresentation.resolve(layout: layout, usesSidebarShell: false)
    #expect(presentation.navigation == .tabs)
    #expect(presentation.usesDrawer)
    #expect(presentation.sections(profile: .player)
        == [.songs, .suggestions, .leaderboards, .rivals, .statistics, .settings])
    #expect(presentation.sections(profile: .none) == [.songs, .leaderboards, .settings])
}

/// iPad/macOS: the sidebar shell always uses the regular set, even before the first
/// geometry pass publishes a layout (the default is `.standardPhone`).
@Test(arguments: [DeviceLayout.standardPhone, Layouts.largeIPhoneLandscape])
func sidebarShellUsesRegularSections(layout: DeviceLayout) {
    let presentation = ShellPresentation.resolve(layout: layout, usesSidebarShell: true)
    #expect(presentation == ShellPresentation(navigation: .sidebar, usesRegularSectionSet: true))
    #expect(!presentation.usesDrawer)
}

/// Folding and unfolding swap Compete and Leaderboards in place (same slot).
@Test func foldTransitionKeepsEquivalentSection() {
    let folded = ShellPresentation.resolve(layout: Layouts.duoFoldedPortrait, usesSidebarShell: false)
        .sections(profile: .player)
    let unfolded = ShellPresentation.resolve(layout: Layouts.duoUnfolded, usesSidebarShell: false)
        .sections(profile: .player)
    #expect(FestivalTabPolicy.resolve(.compete, in: unfolded) == .leaderboards)
    #expect(FestivalTabPolicy.resolve(.leaderboards, in: folded) == .compete)
    #expect(FestivalTabPolicy.resolve(.rivals, in: folded) == .compete)
}

/// Once Leaderboards and Rivals are tabs (Duo unfolded) their drawer rows switch tabs.
@Test func unfoldedDrawerDropsSplitTabs() {
    let visible = ShellPresentation.resolve(layout: Layouts.duoUnfolded, usesSidebarShell: false)
        .sections(profile: .player)
    let items = DrawerMenu.browse(profile: .player, visibleSections: visible, hideShop: false)
    #expect(items.first { $0.id == "rivals" }?.intent == .select(.rivals))
    #expect(items.first { $0.id == "leaderboards" }?.intent == .select(.leaderboards))
}

// MARK: - Drawer placement

/// Ordinary iPhones keep the original drawer geometry exactly (pixel-identical).
@Test func iPhoneDrawerPlacementUnchanged() {
    let safeArea = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
    let size = CGSize(width: 402, height: 874 - 62 - 34)
    let placement = DrawerPlacement.resolve(size: size, safeArea: safeArea, layout: Layouts.iPhonePortrait)
    #expect(placement.width == min(340, 402 * 0.84))
    #expect(placement.panelPadding == EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    #expect(placement.contentTop == CGFloat(62 - 8 + 4))
    #expect(placement.contentBottom == CGFloat(34))
    #expect(placement.scrimInsets == EdgeInsets())
}

/// In every folded rotation the panel stays clear of the vertical bar and the camera,
/// and the scrim leaves the vertical bar uncovered.
@Test(arguments: Layouts.foldedRotations)
func duoDrawerAvoidsBarAndCamera(layout: DeviceLayout) {
    let window = layout.orientation == .portrait
        ? CGSize(width: 466, height: 678) : CGSize(width: 678, height: 466)
    let safeArea = layout.overlayInsets
    let inner = CGSize(
        width: window.width - safeArea.leading - safeArea.trailing,
        height: window.height - safeArea.top - safeArea.bottom
    )
    let placement = DrawerPlacement.resolve(size: inner, safeArea: safeArea, layout: layout)
    let panel = placement.panelFrame(in: window)
    let bounds = CGRect(origin: .zero, size: window)
    let reserved = layout.overlayInsets
    let usable = CGRect(
        x: reserved.leading, y: reserved.top,
        width: window.width - reserved.leading - reserved.trailing,
        height: window.height - reserved.top - reserved.bottom
    )
    #expect(usable.contains(panel), "panel \(panel) leaves the reserved-free area \(usable)")
    #expect(panel.width > 200)
    guard case let .verticalBar(edge) = layout.sectionChrome else {
        Issue.record("folded layouts have a vertical bar")
        return
    }
    let bar = edge == .leading
        ? CGRect(x: 0, y: 0, width: reserved.leading, height: window.height)
        : CGRect(x: window.width - reserved.trailing, y: 0, width: reserved.trailing, height: window.height)
    #expect(!panel.intersects(bar))
    let scrim = CGRect(
        x: placement.scrimInsets.leading, y: 0,
        width: window.width - placement.scrimInsets.leading - placement.scrimInsets.trailing,
        height: window.height
    )
    #expect(scrim.intersection(bar).width == 0, "scrim \(scrim) covers the bar \(bar)")
    #expect(bounds.contains(panel))
}

// MARK: - Drawer corners

/// The panel follows the display's corners through the system's concentric shape, with a
/// floor that keeps it concentric with its own rows where no display corner applies.
@Test func drawerCornersAreConcentricWithAMinimum() {
    #expect(DrawerCorners.minimumRadius == DrawerCorners.rowRadius + DrawerCorners.contentInset)
    #expect(DrawerCorners.minimumRadius == 26)
    if #available(iOS 26.0, macOS 26.0, *) {
        #expect(DrawerCorners.panelCornerStyle == .concentric(minimum: .fixed(26)))
        #expect(DrawerCorners.panelCornerStyle != .fixed(DrawerCorners.legacyRadius))
    }
}

/// The scrim's cut-out is laid out at the panel's window position in every pose, so its
/// position-dependent corners match the panel's.
@Test(arguments: [Layouts.iPhonePortrait] + Layouts.foldedRotations)
func drawerCutoutSitsOnThePanel(layout: DeviceLayout) {
    let window = layout.pose == .standard
        ? CGSize(width: 402, height: 874)
        : layout.orientation == .portrait ? CGSize(width: 466, height: 678) : CGSize(width: 678, height: 466)
    let safeArea = layout.pose == .standard
        ? EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0) : layout.overlayInsets
    let inner = CGSize(
        width: window.width - safeArea.leading - safeArea.trailing,
        height: window.height - safeArea.top - safeArea.bottom
    )
    let placement = DrawerPlacement.resolve(size: inner, safeArea: safeArea, layout: layout)
    let cutout = placement.cutoutPadding
    #expect(placement.scrimInsets.leading + cutout.leading == placement.panelPadding.leading)
    #expect(placement.scrimInsets.top + cutout.top == placement.panelPadding.top)
    #expect(placement.scrimInsets.bottom + cutout.bottom == placement.panelPadding.bottom)
    #expect(cutout.leading >= 0 && cutout.top >= 0 && cutout.bottom >= 0)
}

// MARK: - Root profile item

/// Vertical bars need a titled symbol; horizontal bars keep the monogram (B1).
@Test func profileItemPresentationPerChrome() {
    typealias Presentation = RootProfileButton.Presentation
    #expect(Presentation.resolve(displayName: nil, chrome: .verticalBar(.trailing)) == .choose)
    #expect(Presentation.resolve(displayName: nil, chrome: .tabBar) == .choose)
    #expect(Presentation.resolve(displayName: "Fixture", chrome: .tabBar) == .monogram("Fixture"))
    #expect(Presentation.resolve(displayName: "Fixture", chrome: .sidebar) == .monogram("Fixture"))
    #expect(Presentation.resolve(displayName: "Fixture", chrome: .verticalBar(.leading))
        == .symbol(title: "Profile: Fixture"))
}

/// Shelved dual-source path: inner portrait would keep the compact set (Compete).
@Test func duoInnerPortraitKeepsCompeteWhenDualSourceEnabled() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
    ), dualSource: true)
    let presentation = ShellPresentation.resolve(layout: layout, usesSidebarShell: false)
    #expect(presentation == ShellPresentation(navigation: .tabs, usesRegularSectionSet: false))
    #expect(presentation.sections(profile: .player)
        == [.songs, .suggestions, .compete, .settings])
}

// MARK: - Search tab slot (issue #92)

/// Five phone tabs plus Search would move Search into "More": Statistics goes first.
@Test func searchTabDropsStatisticsFirst() {
    #expect(FestivalTabPolicy.fittingSearchTab([.songs, .suggestions, .compete, .statistics, .settings])
        == [.songs, .suggestions, .compete, .settings])
    #expect(FestivalTabPolicy.fittingSearchTab([.songs, .suggestions, .leaderboards, .statistics, .settings])
        == [.songs, .suggestions, .leaderboards, .settings])
}

/// Sets that already fit are unchanged (anonymous: Songs · Leaderboards · Settings).
@Test func searchTabKeepsSetsThatFit() {
    #expect(FestivalTabPolicy.fittingSearchTab([.songs, .leaderboards, .settings]) == [.songs, .leaderboards, .settings])
    #expect(ShellPresentation(navigation: .tabs, usesRegularSectionSet: false).sections(profile: .none)
        == [.songs, .leaderboards, .settings])
}

/// Every compact set fits beside Search, and Songs, Compete and Settings are never dropped.
@Test func searchTabAlwaysFits() {
    for profile in [FestivalProfileKind.none, .player, .band] {
        let all = FestivalTabPolicy.sections(profile: profile, regularWidth: false)
        let fitted = FestivalTabPolicy.fittingSearchTab(all)
        #expect(fitted.count + 1 <= FestivalTabPolicy.phoneTabLimit)
        for kept: FestivalSection in [.songs, .compete, .settings] where all.contains(kept) {
            #expect(fitted.contains(kept))
        }
        #expect(fitted == all.filter(fitted.contains), "order is preserved")
    }
}

/// A dropped section stays in the drawer, which pushes it on the current stack.
@Test func droppedStatisticsOpensFromDrawer() {
    let visible = ShellPresentation(navigation: .tabs, usesRegularSectionSet: false).sections(profile: .player)
    let row = DrawerMenu.browse(profile: .player, visibleSections: visible, hideShop: false)
        .first { $0.id == FestivalSection.statistics.rawValue }
    #expect(row?.intent == .push(.statistics))
}

/// A launch naming a section the phone dropped for Search pushes the drawer's page.
@Test func droppedSectionOpensAsDrawerRoute() {
    let visible = ShellPresentation(navigation: .tabs, usesRegularSectionSet: false).sections(profile: .player)
    #expect(FestivalTabPolicy.searchTabOverflowRoute(for: .statistics, profile: .player, visible: visible)
        == .statistics)
    // Visible tabs and sections the profile cannot show at all are not pushed.
    #expect(FestivalTabPolicy.searchTabOverflowRoute(for: .compete, profile: .player, visible: visible) == nil)
    #expect(FestivalTabPolicy.searchTabOverflowRoute(for: .statistics, profile: .none, visible: [.songs, .leaderboards, .settings])
        == nil)
    #expect(FestivalTabPolicy.searchTabOverflowRoute(for: .settings, profile: .player, visible: []) == nil)
    let sidebar = FestivalTabPolicy.sections(profile: .player, regularWidth: true)
    #expect(FestivalTabPolicy.searchTabOverflowRoute(for: .statistics, profile: .player, visible: sidebar) == nil)
}

// MARK: - Deferred section-set changes

/// A fold or unfold changes the tabs one run-loop turn after the size class (the
/// inner-portrait fold crashed UIKit's tab rebuild when both changed together):
/// the applied set wins for tabs, the resolved set until one is applied, and the
/// sidebar shell never defers.
@Test func pendingSectionSetKeepsTheAppliedTabs() {
    let folded = ShellPresentation.resolve(layout: Layouts.duoFoldedPortrait, usesSidebarShell: false)
    let unfolded = ShellPresentation.resolve(layout: Layouts.duoUnfolded, usesSidebarShell: false)
    #expect(ShellPresentation.applying(folded, regularSet: true).usesRegularSectionSet)
    #expect(!ShellPresentation.applying(unfolded, regularSet: false).usesRegularSectionSet)
    #expect(ShellPresentation.applying(unfolded, regularSet: nil) == unfolded)
    #expect(ShellPresentation.applying(folded, regularSet: false) == folded)
    let sidebar = ShellPresentation.resolve(layout: .standardPhone, usesSidebarShell: true)
    #expect(ShellPresentation.applying(sidebar, regularSet: false) == sidebar)
}
