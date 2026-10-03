import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - Fold-avoiding placement (issue #99)

/// A container below the scope bar on the Duo inner display (window coordinates).
private let container = CGRect(x: 0, y: 200, width: 669, height: 700)

@Test func noFoldKeepsTheWholeContainer() {
    #expect(FoldAvoidingPlacement.region(container: container, fold: nil)
            == CGRect(x: 0, y: 0, width: 669, height: 700))
}

@Test func horizontalFoldPicksTheTallerSide() {
    // Fold at y 470–490: 270 pt above (inside the container), 410 pt below.
    let fold = CGRect(x: 0, y: 470, width: 669, height: 20)
    #expect(FoldAvoidingPlacement.region(container: container, fold: fold)
            == CGRect(x: 0, y: 290, width: 669, height: 410))
    // Fold low in the container: the top side wins.
    let low = CGRect(x: 0, y: 700, width: 669, height: 20)
    #expect(FoldAvoidingPlacement.region(container: container, fold: low)
            == CGRect(x: 0, y: 0, width: 669, height: 500))
}

@Test func verticalFoldPicksTheWiderSideLeadingOnATie() {
    let wide = CGRect(x: 0, y: 100, width: 951, height: 560)
    let fold = CGRect(x: 465, y: 0, width: 21, height: 669)
    #expect(FoldAvoidingPlacement.region(container: wide, fold: fold)
            == CGRect(x: 0, y: 0, width: 465, height: 560))
    let offset = CGRect(x: 300, y: 0, width: 21, height: 669)
    #expect(FoldAvoidingPlacement.region(container: wide, fold: offset)
            == CGRect(x: 321, y: 0, width: 630, height: 560))
}

@Test func foldOutsideOrTooTightKeepsTheWholeContainer() {
    let whole = CGRect(x: 0, y: 0, width: 669, height: 700)
    // Fold above the container (the scope bar region).
    #expect(FoldAvoidingPlacement.region(
        container: container, fold: CGRect(x: 0, y: 100, width: 669, height: 20)) == whole)
    // Fold beside a narrow container (a split column that ends before it).
    #expect(FoldAvoidingPlacement.region(
        container: CGRect(x: 0, y: 0, width: 300, height: 600),
        fold: CGRect(x: 465, y: 0, width: 21, height: 669)) == CGRect(x: 0, y: 0, width: 300, height: 600))
    // Both sides of a centred fold in a short container are under the minimum.
    #expect(FoldAvoidingPlacement.region(
        container: CGRect(x: 0, y: 0, width: 669, height: 300),
        fold: CGRect(x: 0, y: 140, width: 669, height: 20)) == CGRect(x: 0, y: 0, width: 669, height: 300))
}
