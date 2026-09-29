import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// Shelved dual-source path (`DualSourcePolicy.isEnabled` is false): fixtures resolve
/// with `dualSource: true`. iPhone Duo windows (points; `.agents/platforms/apple/duo.md`). The portrait fold is
/// representative: a horizontal division across the middle of the inner display.
private enum DualLayouts {
    static let innerPortraitFold = CGRect(x: 0, y: 463, width: 669, height: 25)

    static let halfFoldPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 44, leading: 0, bottom: 20, trailing: 0),
        hinge: .partiallyOpen, divisions: [innerPortraitFold]
    ), dualSource: true)
    static let unfoldedPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
    ), dualSource: true)
    static let unfoldedLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    static let halfFoldLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular, verticalBarEdge: .trailing,
        hinge: .partiallyOpen, divisions: [CGRect(x: 455, y: 0, width: 41, height: 669)]
    ))
    static let folded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    ))
    static let iPhone = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 402, height: 874), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
    ))
    static let iPad = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 834, height: 1194), widthClass: .regular, usesSidebarShell: true
    ))
}

// MARK: - Mode per pose

/// Partially open in portrait: divide on the fold.
@Test func dualSourceDividesOnPortraitFold() {
    #expect(DualSourcePolicy.mode(DualLayouts.halfFoldPortrait) == .atFold(DualLayouts.innerPortraitFold))
    #expect(DualSourcePolicy.isActive(DualLayouts.halfFoldPortrait))
}

/// Flat in portrait: the same two regions, divided proportionally.
@Test func dualSourceIsProportionalWhenFlatPortrait() {
    #expect(DualSourcePolicy.mode(DualLayouts.unfoldedPortrait) == .proportional)
}

/// Every other window shows the primary content alone.
@Test(arguments: [
    DualLayouts.unfoldedLandscape, DualLayouts.halfFoldLandscape, DualLayouts.folded,
    DualLayouts.iPhone, DualLayouts.iPad, DeviceLayout.standardPhone,
])
func dualSourceSingleElsewhere(layout: DeviceLayout) {
    #expect(DualSourcePolicy.mode(layout) == .single)
    #expect(!DualSourcePolicy.isActive(layout))
    #expect(DualSourcePolicy.regions(mode: DualSourcePolicy.mode(layout), container: CGRect(x: 0, y: 0, width: 669, height: 900)) == nil)
}

// MARK: - Regions

/// The primary region ends where the fold begins; the secondary starts where it ends.
@Test func dualSourceRegionsMeetTheFold() throws {
    // Container: below a 44 pt top bar, above a 70 pt tab bar.
    let container = CGRect(x: 0, y: 44, width: 669, height: 951 - 44 - 70)
    let fold = DualLayouts.innerPortraitFold
    let regions = try #require(DualSourcePolicy.regions(mode: .atFold(fold), container: container))
    #expect(regions.primary == fold.minY - container.minY)
    #expect(regions.gap == fold.height)
    #expect(regions.primary + regions.gap + regions.secondary == container.height)
    #expect(container.minY + regions.primary + regions.gap == fold.maxY)
}

/// A hairline division still gets a small untouchable gutter, centred on the fold.
@Test func dualSourceWidensHairlineFold() throws {
    let container = CGRect(x: 0, y: 0, width: 669, height: 900)
    let fold = CGRect(x: 0, y: 450, width: 669, height: 0)
    let regions = try #require(DualSourcePolicy.regions(mode: .atFold(fold), container: container))
    #expect(regions.gap == DualSourcePolicy.minimumFoldGap)
    #expect(regions.primary == 450 - DualSourcePolicy.minimumFoldGap / 2)
}

/// A fold that leaves too little on one side (or misses the container) falls back to
/// the proportional split inside the container.
@Test(arguments: [
    CGRect(x: 0, y: 60, width: 669, height: 25),  // too close to the top
    CGRect(x: 0, y: 2000, width: 669, height: 25),  // below the container
])
func dualSourceFoldFallback(fold: CGRect) throws {
    let container = CGRect(x: 0, y: 44, width: 669, height: 800)
    let regions = try #require(DualSourcePolicy.regions(mode: .atFold(fold), container: container))
    #expect(regions == DualSourcePolicy.regions(mode: .proportional, container: container))
}

/// Flat: ``DualSourcePolicy/primaryShare`` of the height above a fixed gutter.
@Test func dualSourceProportionalShares() throws {
    let container = CGRect(x: 0, y: 0, width: 669, height: 812)
    let regions = try #require(DualSourcePolicy.regions(mode: .proportional, container: container))
    #expect(regions.gap == DualSourcePolicy.proportionalGap)
    #expect(regions.primary == ((812 - 12) * DualSourcePolicy.primaryShare).rounded())
    #expect(regions.primary + regions.gap + regions.secondary == 812)
}

/// A container too short for two useful regions (or not yet measured) shows one.
@Test(arguments: [CGFloat(0), 200])
func dualSourceNeedsRoom(height: CGFloat) {
    let container = CGRect(x: 0, y: 0, width: 669, height: height)
    #expect(DualSourcePolicy.regions(mode: .proportional, container: container) == nil)
}

// MARK: - Debug pose override

/// `FST_DEBUG_DUO_POSE` parses its two values and ignores anything else.
@Test func debugDuoPoseParses() {
    #expect(DebugDuoPose.parse("half-portrait") == .halfPortrait)
    #expect(DebugDuoPose.parse("unfolded-portrait") == .unfoldedPortrait)
    #expect(DebugDuoPose.parse("half") == nil)
    #expect(DebugDuoPose.parse(nil) == nil)
}

/// The half-portrait override on the folded outer display yields a mid-height fold
/// and the dual-source arrangement, keeping the real bar and size class.
@Test func debugHalfPortraitOnOuterDisplay() throws {
    let observed = LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    )
    let layout = DeviceLayout.resolve(DebugDuoPose.halfPortrait.apply(to: observed), dualSource: true)
    let fold = try #require(layout.foldFrame)
    #expect(fold.midY == 339)
    #expect(layout.pose == .partiallyFolded)
    #expect(layout.sectionChrome == .verticalBar(.trailing))
    #expect(layout.widthClass == .compact)
    #expect(DualSourcePolicy.mode(layout) == .atFold(fold))
    #expect(!layout.usesRegularSectionSet)
}

/// The unfolded-portrait override removes any fold and splits proportionally.
@Test func debugUnfoldedPortraitIsProportional() {
    let observed = LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact, verticalBarEdge: .trailing, hinge: .closed
    )
    let layout = DeviceLayout.resolve(DebugDuoPose.unfoldedPortrait.apply(to: observed), dualSource: true)
    #expect(layout.pose == .unfolded)
    #expect(DualSourcePolicy.mode(layout) == .proportional)
}

/// Before the first geometry pass (zero size) the override changes nothing.
@Test func debugPoseIgnoresUnmeasuredWindow() {
    let observed = LayoutSignals(size: .zero, widthClass: .compact)
    #expect(DebugDuoPose.halfPortrait.apply(to: observed) == observed)
}

// MARK: - Shelved by default

/// Operator 2026-09-28: with the default (flag off) the portrait debug overrides and
/// the inner display in portrait resolve to a normal single-region layout.
@Test func dualSourceShelvedByDefault() {
    #expect(!DualSourcePolicy.isEnabled)
    let observed = LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact, verticalBarEdge: .trailing, hinge: .closed
    )
    for pose in [DebugDuoPose.halfPortrait, .unfoldedPortrait] {
        #expect(DualSourcePolicy.mode(DeviceLayout.resolve(pose.apply(to: observed))) == .single)
    }
    let innerHalf = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .partiallyOpen,
        divisions: [CGRect(x: 0, y: 463, width: 669, height: 25)]
    ))
    #expect(DualSourcePolicy.mode(innerHalf) == .single)
}
