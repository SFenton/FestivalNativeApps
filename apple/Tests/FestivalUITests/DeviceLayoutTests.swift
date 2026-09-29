import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Fixtures

/// Measured/derived iPhone Duo geometry (points): outer 466×678, inner 669×951
/// (`.agents/platforms/apple/duo.md`). Insets are representative, not asserted device truth.
private enum Duo {
    static let outerPortrait = CGSize(width: 466, height: 678)
    static let outerLandscape = CGSize(width: 678, height: 466)
    static let innerLandscape = CGSize(width: 951, height: 669)
    static let innerPortrait = CGSize(width: 669, height: 951)
    /// Outer camera in the top-trailing corner, beside the vertical bar.
    static let cameraTopTrailing = CGRect(x: 404, y: 8, width: 44, height: 36)
}

// MARK: - Pose and chrome

/// An ordinary iPhone: no hinge, no vertical bar, horizontal tabs, one column.
@Test func standardPhoneKeepsTabBar() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 402, height: 874), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
    ))
    #expect(layout.pose == .standard)
    #expect(layout.orientation == .portrait)
    #expect(layout.sectionChrome == .tabBar)
    #expect(layout.contentArrangement == .stack)
    #expect(!layout.usesRegularSectionSet)
    #expect(layout.overlayInsets == EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
    #expect(layout.foldFrame == nil)
}

/// Folded Duo: the system vertical bar carries the tabs; one column; compact section set.
@Test func foldedPortraitUsesSystemVerticalBar() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.outerPortrait, widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    ))
    #expect(layout.pose == .folded)
    #expect(layout.sectionChrome == .verticalBar(.trailing))
    #expect(layout.contentArrangement == .stack)
    #expect(!layout.usesRegularSectionSet)
}

/// Rotating the closed device moves the bar with the camera (leading in landscape here).
@Test func foldedLandscapeFollowsBarEdge() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.outerLandscape, widthClass: .compact,
        verticalBarEdge: .leading, hinge: .closed
    ))
    #expect(layout.pose == .folded)
    #expect(layout.orientation == .landscape)
    #expect(layout.sectionChrome == .verticalBar(.leading))
}

/// Unfolded landscape: bar stays vertical, pages become list/detail, regular section set.
@Test func unfoldedLandscapeIsListDetail() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.innerLandscape, widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    #expect(layout.pose == .unfolded)
    #expect(layout.orientation == .landscape)
    #expect(layout.sectionChrome == .verticalBar(.trailing))
    #expect(layout.contentArrangement == .listDetail)
    #expect(layout.usesRegularSectionSet)
}

/// Unfolded portrait: the system returns to horizontal bars (no vertical-bar edge);
/// list/detail and the regular section set, as in landscape (dual-source shelved).
@Test func unfoldedPortraitReturnsToTabBar() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.innerPortrait, widthClass: .regular, verticalBarEdge: nil, hinge: .fullyOpen
    ))
    #expect(layout.pose == .unfolded)
    #expect(layout.sectionChrome == .tabBar)
    #expect(layout.contentArrangement == .listDetail)
    #expect(layout.usesRegularSectionSet)
}

/// Operator 2026-09-28: half-open portrait is the normal portrait layout too.
@Test func partiallyFoldedPortraitIsNormalPortrait() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.innerPortrait, widthClass: .regular, hinge: .partiallyOpen,
        divisions: [CGRect(x: 0, y: 463, width: 669, height: 25)]
    ))
    #expect(!DualSourcePolicy.isEnabled)
    #expect(layout.contentArrangement == .listDetail)
    #expect(layout.usesRegularSectionSet)
}

/// Shelved path (flag on): the fold runs across the screen; two stacked regions.
@Test func partiallyFoldedPortraitStacksRegionsWhenEnabled() {
    let fold = CGRect(x: 0, y: 463, width: 669, height: 25)
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.innerPortrait, widthClass: .regular, hinge: .partiallyOpen, divisions: [fold]
    ), dualSource: true)
    #expect(layout.pose == .partiallyFolded)
    #expect(layout.orientation == .portrait)
    #expect(layout.contentArrangement == .dualSource)
    #expect(layout.foldFrame == fold)
    #expect(!layout.usesRegularSectionSet)
}

/// Partially open in landscape (book): the vertical fold keeps list/detail columns.
@Test func partiallyFoldedLandscapeKeepsListDetail() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.innerLandscape, widthClass: .regular, verticalBarEdge: .trailing,
        hinge: .partiallyOpen, divisions: [CGRect(x: 455, y: 0, width: 41, height: 669)]
    ))
    #expect(layout.contentArrangement == .listDetail)
    #expect(layout.usesRegularSectionSet)
}

/// Other portrait windows never stack regions: iPhone, folded Duo, iPad sidebar.
@Test func onlyDuoInnerPortraitStacksRegions() {
    let iPhone = DeviceLayout.resolve(LayoutSignals(size: CGSize(width: 402, height: 874), widthClass: .compact), dualSource: true)
    let folded = DeviceLayout.resolve(LayoutSignals(
        size: Duo.outerPortrait, widthClass: .compact, verticalBarEdge: .trailing, hinge: .closed
    ), dualSource: true)
    let iPadPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 834, height: 1194), widthClass: .regular, hinge: .fullyOpen, usesSidebarShell: true
    ), dualSource: true)
    #expect(iPhone.contentArrangement == .stack)
    #expect(folded.contentArrangement == .stack)
    #expect(iPadPortrait.contentArrangement == .listDetail)
}

/// An active division means partially folded, and exposes the fold for custom overlays.
@Test func activeDivisionIsPartiallyFolded() {
    let fold = CGRect(x: 455, y: 0, width: 41, height: 669)
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.innerLandscape, widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .fullyOpen, divisions: [fold]
    ))
    #expect(layout.pose == .partiallyFolded)
    #expect(layout.foldFrame == fold)
}

/// A partially open hinge is partially folded on the inner display, but still folded
/// while the compact outer display is showing (mid-transition or tent pose).
@Test(arguments: [(WidthClass.regular, DeviceLayout.Pose.partiallyFolded), (.compact, .folded)])
func partiallyOpenHinge(widthClass: WidthClass, expected: DeviceLayout.Pose) {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: widthClass == .regular ? Duo.innerLandscape : Duo.outerPortrait,
        widthClass: widthClass, hinge: .partiallyOpen
    ))
    #expect(layout.pose == expected)
}

/// Without hinge updates, the vertical bar alone still identifies the Duo pose.
@Test(arguments: [(WidthClass.compact, DeviceLayout.Pose.folded), (.regular, .unfolded)])
func verticalBarFallbackPose(widthClass: WidthClass, expected: DeviceLayout.Pose) {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.outerPortrait, widthClass: widthClass, verticalBarEdge: .trailing, hinge: nil
    ))
    #expect(layout.pose == expected)
}

/// The iPad/macOS split shell keeps its sidebar regardless of other signals.
@Test func sidebarShellWins() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 1210, height: 834), widthClass: .regular,
        verticalBarEdge: .trailing, usesSidebarShell: true
    ))
    #expect(layout.sectionChrome == .sidebar)
    #expect(layout.contentArrangement == .listDetail)
    #expect(layout.pose == .unfolded)
}

// MARK: - Cutout-safe insets

/// The outer camera sits above a zero top safe area; overlays must clear it.
@Test func cameraOcclusionRaisesTopOverlayInset() {
    let layout = DeviceLayout.resolve(LayoutSignals(
        size: Duo.outerPortrait, widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed, occlusions: [Duo.cameraTopTrailing]
    ))
    #expect(layout.overlayInsets.top == 44)
    #expect(layout.overlayInsets.trailing == 84)
    #expect(layout.overlayInsets.bottom == 34)
    #expect(layout.overlayInsets.leading == 0)
}

/// An occlusion nearest a side edge pushes that side, never below the safe area.
@Test func sideOcclusionPushesNearestEdge() {
    let bounds = CGRect(origin: .zero, size: Duo.outerLandscape)
    let camera = CGRect(x: 6, y: 200, width: 30, height: 40)
    let insets = DeviceLayout.overlayInsets(
        safeArea: EdgeInsets(top: 0, leading: 20, bottom: 21, trailing: 0),
        occlusions: [camera], bounds: bounds
    )
    #expect(insets.leading == 36)
    #expect(insets.top == 0)

    let wide = DeviceLayout.overlayInsets(
        safeArea: EdgeInsets(top: 0, leading: 84, bottom: 0, trailing: 0),
        occlusions: [camera], bounds: bounds
    )
    #expect(wide.leading == 84)
}

/// Occlusions entirely outside the window (e.g. the other display) are ignored.
@Test func offscreenOcclusionIgnored() {
    let insets = DeviceLayout.overlayInsets(
        safeArea: EdgeInsets(), occlusions: [CGRect(x: 900, y: 10, width: 40, height: 40)],
        bounds: CGRect(origin: .zero, size: Duo.outerPortrait)
    )
    #expect(insets == EdgeInsets())
}

/// Bottom-edge occlusions (upside-down outer display) push the bottom inset.
@Test func bottomOcclusionPushesBottom() {
    let insets = DeviceLayout.overlayInsets(
        safeArea: EdgeInsets(), occlusions: [CGRect(x: 18, y: 634, width: 44, height: 36)],
        bounds: CGRect(origin: .zero, size: Duo.outerPortrait)
    )
    #expect(insets.bottom == 44)
    #expect(insets.leading == 0)
}

// MARK: - Environment default

/// Hosted tests and previews without the root publisher see an ordinary phone.
@Test func environmentDefaultsToStandardPhone() {
    #expect(EnvironmentValues().deviceLayout == .standardPhone)
}

// MARK: - Insets inside the safe area

/// Content laid out inside the safe area already clears the vertical bar; only the
/// camera occlusion beyond it remains (no double rail inset beside a scrubber).
@Test func cutoutInsetsExcludeTheSafeArea() {
    let folded = DeviceLayout.resolve(LayoutSignals(
        size: Duo.outerPortrait, widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed, occlusions: [Duo.cameraTopTrailing]
    ))
    #expect(folded.overlayInsets.trailing == 84)
    #expect(folded.cutoutInsets.trailing == 0)
    #expect(folded.cutoutInsets.top == Duo.cameraTopTrailing.maxY)
    #expect(DeviceLayout.standardPhone.cutoutInsets == EdgeInsets())
}
