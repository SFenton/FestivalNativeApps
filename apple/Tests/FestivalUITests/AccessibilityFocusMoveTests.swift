import CoreGraphics
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// The element an on-demand split or the flyout gives assistive-technology focus to
/// (`AccessibilityFocusChoice`, `.agents/testing/apple/voiceover.md`).
struct AccessibilityFocusMoveTests {
    private typealias Candidate = AccessibilityFocusChoice.Candidate

    /// The iPad landscape split: leading pane 0–604.5, trailing 605.5–1210.
    private let trailing = CGRect(x: 605.5, y: 0, width: 604.5, height: 834)

    @Test func topHeadingPicksThePanesTitleNotTheLeadingTitle() {
        let candidates = [
            Candidate(label: "Lead Rankings", identifier: "", frame: CGRect(x: 20, y: 60, width: 200, height: 40), isHeading: true),
            Candidate(label: "Close", identifier: "fst.split.close", frame: CGRect(x: 620, y: 20, width: 44, height: 44), isHeading: false),
            Candidate(label: "Global Statistics", identifier: "", frame: CGRect(x: 625, y: 300, width: 200, height: 30), isHeading: true),
            Candidate(label: "Fixture Player 2", identifier: "", frame: CGRect(x: 625, y: 60, width: 300, height: 40), isHeading: true),
        ]
        #expect(AccessibilityFocusChoice.topHeading(candidates, in: trailing) == 3)
    }

    @Test func topHeadingBreaksTiesLeadingFirstAndSkipsEmptyOrZeroSize() {
        let candidates = [
            Candidate(label: "", identifier: "", frame: CGRect(x: 610, y: 10, width: 100, height: 20), isHeading: true),
            Candidate(label: "Hidden", identifier: "", frame: CGRect(x: 610, y: 5, width: 0, height: 0), isHeading: true),
            Candidate(label: "Right", identifier: "", frame: CGRect(x: 900, y: 60.5, width: 100, height: 30), isHeading: true),
            Candidate(label: "Left", identifier: "", frame: CGRect(x: 640, y: 60, width: 100, height: 30), isHeading: true),
        ]
        #expect(AccessibilityFocusChoice.topHeading(candidates, in: trailing) == 3)
    }

    @Test func topHeadingIsNilWithoutAHeadingInTheRegion() {
        let candidates = [
            Candidate(label: "Lead Rankings", identifier: "", frame: CGRect(x: 20, y: 60, width: 200, height: 40), isHeading: true),
            Candidate(label: "Row", identifier: "", frame: CGRect(x: 640, y: 160, width: 400, height: 60), isHeading: false),
        ]
        #expect(AccessibilityFocusChoice.topHeading(candidates, in: trailing) == nil)
    }

    @Test func traceNamesAreShortAndKeyed() {
        #expect(AppRoute.player(accountId: "abc", displayName: "X").focusTraceName == "player:abc")
        #expect(AppRoute.rivalDetail(rivalId: "r1", name: nil, scope: nil).focusTraceName == "rivalDetail:r1")
        #expect(AppRoute.licenses.focusTraceName == "licenses")
    }
}

/// Song Detail's eager card rows at accessibility sizes keep the lazy grid's columns.
struct SongDetailCardColumnsTests {
    private func columns(_ width: CGFloat) -> Int {
        HingeEagerGridLayout(
            minimum: SongDetailCardColumns.minimumWidth, spacing: SongDetailCardColumns.spacing,
            rowSpacing: SongDetailCardColumns.rowSpacing
        ).columns(width: width).count
    }

    @Test func columnsMatchTheAdaptiveGrid() {
        #expect(columns(802) == 2)   // iPad portrait, 834 − 32
        #expect(columns(343) == 1)   // ⅓ window / iPhone
        #expect(columns(1178) == 3)  // iPad landscape
        #expect(columns(0) == 1)
    }
}
