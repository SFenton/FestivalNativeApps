import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Pager screen placement (issue #345)

/// A full-width board's pager row on the Duo inner display in landscape, left of a
/// trailing vertical bar (window coordinates).
private let board = CGRect(x: 0, y: 600, width: 880, height: 60)

@Test func noHingeCentresAcrossTheBoard() {
    #expect(PagerScreenPlacement.region(container: board, hinge: nil, preferredEdge: .trailing) == nil)
}

@Test func unfoldedHingeMovesThePagerBesideTheVerticalBar() {
    // The inner display's middle line (no reported hinge) at x 475.5.
    let middle = CGRect(x: 475.5, y: 0, width: 0, height: 669)
    #expect(PagerScreenPlacement.region(container: board, hinge: middle, preferredEdge: .trailing)
            == CGRect(x: 475.5, y: 0, width: 404.5, height: 60))
    // A real fold band: the pager starts after it.
    let fold = CGRect(x: 465, y: 0, width: 21, height: 669)
    #expect(PagerScreenPlacement.region(container: board, hinge: fold, preferredEdge: .trailing)
            == CGRect(x: 486, y: 0, width: 394, height: 60))
    // A leading vertical bar puts it on the leading screen.
    let trailingBoard = CGRect(x: 71, y: 600, width: 880, height: 60)
    #expect(PagerScreenPlacement.region(container: trailingBoard, hinge: fold, preferredEdge: .leading)
            == CGRect(x: 0, y: 0, width: 394, height: 60))
}

@Test func narrowPreferredSideFallsBackToTheOtherScreen() {
    let offset = CGRect(x: 600, y: 0, width: 21, height: 669)
    #expect(PagerScreenPlacement.region(container: board, hinge: offset, preferredEdge: .trailing)
            == CGRect(x: 0, y: 0, width: 600, height: 60))
}

@Test func hingeOutsideTheBoardOrHorizontalKeepsTheWholeBoard() {
    let fold = CGRect(x: 465, y: 0, width: 21, height: 669)
    // A split's trailing pane already lies on one screen.
    let pane = CGRect(x: 486, y: 600, width: 394, height: 60)
    #expect(PagerScreenPlacement.region(container: pane, hinge: fold, preferredEdge: .trailing) == nil)
    // Inner portrait: the hinge runs across the board, which keeps its centre.
    let portrait = CGRect(x: 0, y: 470, width: 669, height: 0)
    #expect(PagerScreenPlacement.region(
        container: CGRect(x: 0, y: 800, width: 669, height: 60), hinge: portrait, preferredEdge: .trailing) == nil)
    // Both sides too narrow for the pager.
    #expect(PagerScreenPlacement.region(
        container: CGRect(x: 0, y: 600, width: 500, height: 60), hinge: CGRect(x: 250, y: 0, width: 0, height: 669),
        preferredEdge: .trailing) == nil)
}
