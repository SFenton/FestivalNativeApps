import CoreGraphics
import Testing
@testable import FestivalCore

// MARK: - PublicationRefreshFocus

/// VoiceOver stays on the page through an in-place publication refresh (issue #304): the
/// page anchor takes focus when the old content is hidden, keeps it through the spinner,
/// gets it back after the rebuild and retires once the person moves on.
@Suite("PublicationRefreshFocus")
struct PublicationRefreshFocusTests {
    @Test("no refresh, no anchor and no focus request")
    func startsWithoutAnchor() {
        let focus = PublicationRefreshFocus()
        #expect(!focus.showsAnchor)
        #expect(focus.anchorFocusRequest == 0)
    }

    @Test("a refresh shows the anchor, focuses it and restores focus to it after the rebuild")
    func holdsFocusThroughRefresh() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted(focusInPage: true)
        #expect(focus.showsAnchor)
        #expect(focus.anchorFocusRequest == 1, "focus moves to the anchor, not the spinner")

        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: true)
        focus.contentRevealed()
        #expect(focus.showsAnchor, "the anchor survives the rebuild")
        #expect(focus.anchorFocusRequest == 2, "focus is explicitly restored after the rebuild")
    }

    @Test("focus on the spinner at the rebuild is restored to the anchor")
    func spinnerFocusReturnsToAnchor() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted(focusInPage: true)
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: true)
        focus.focusChanged(from: .pageAnchor, to: .spinner, refreshing: true)
        focus.contentRevealed()
        #expect(focus.anchorFocusRequest == 2)
        focus.focusChanged(from: .spinner, to: nil, refreshing: false)
        #expect(focus.showsAnchor, "the spinner leaving with the rebuild does not retire the anchor")
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: false)
        #expect(focus.showsAnchor)
    }

    @Test("moving VoiceOver out of the page during the spinner is respected")
    func leavingDuringRefreshIsNotUndone() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted(focusInPage: true)
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: true)
        focus.focusChanged(from: .pageAnchor, to: nil, refreshing: true)
        focus.contentRevealed()
        #expect(!focus.showsAnchor, "the anchor retires instead of pulling focus back")
        #expect(focus.anchorFocusRequest == 1)
    }

    @Test("returning to the anchor during the spinner restores focus after the rebuild")
    func returningDuringRefreshRestores() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted(focusInPage: true)
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: true)
        focus.focusChanged(from: .pageAnchor, to: nil, refreshing: true)
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: true)
        focus.contentRevealed()
        #expect(focus.showsAnchor)
        #expect(focus.anchorFocusRequest == 2)
    }

    @Test("the anchor retires once the person moves on after the refresh")
    func retiresAfterMovingOn() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted(focusInPage: true)
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: true)
        focus.contentRevealed()
        focus.focusChanged(from: .pageAnchor, to: nil, refreshing: false)
        #expect(!focus.showsAnchor)
    }

    @Test("a second refresh while the anchor still holds focus focuses it again")
    func secondRefresh() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted(focusInPage: true)
        focus.contentRevealed()
        focus.refreshStarted(focusInPage: true)
        #expect(focus.showsAnchor)
        #expect(focus.anchorFocusRequest == 3)
    }

    @Test("focus changes without an anchor and a reveal without a refresh do nothing")
    func idleEventsAreIgnored() {
        var focus = PublicationRefreshFocus()
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: false)
        focus.contentRevealed()
        #expect(focus == PublicationRefreshFocus())
    }

    // MARK: Focus outside the page

    @Test("a refresh while focus is outside the page announces and never moves focus")
    func outsideFocusIsLeftAlone() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted(focusInPage: false)
        #expect(!focus.showsAnchor, "no anchor is added to the page")
        #expect(focus.anchorFocusRequest == 0, "focus is not pulled into the page")
        #expect(focus.announcementRequest == 1, "the visible update is announced instead")
        focus.contentRevealed()
        #expect(focus.anchorFocusRequest == 0, "nor pulled in after the rebuild")
        #expect(!focus.showsAnchor)
    }

    @Test("an outside refresh after an inside one retires the old anchor")
    func outsideAfterInside() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted(focusInPage: true)
        focus.contentRevealed()
        focus.refreshStarted(focusInPage: false)
        #expect(!focus.showsAnchor)
        #expect(focus.anchorFocusRequest == 2)
        #expect(focus.announcementRequest == 1)
    }

    // MARK: Location

    /// A 390×844 phone: page between the navigation bar (y < 100) and tab bar (y > 760).
    private static let page = CGRect(x: 0, y: 100, width: 390, height: 660)

    private static func location(
        focused: CGRect?, inHierarchy: Bool? = nil, onScreen: Bool = true, covered: Bool = false
    ) -> PublicationRefreshFocus.Location {
        PublicationRefreshFocus.Location(
            pageOnScreen: onScreen, pageCovered: covered, pageFrame: page,
            focusedFrame: focused, focusedInPageHierarchy: inHierarchy
        )
    }

    @Test("focus on a row inside the page is inside")
    func rowIsInside() {
        #expect(Self.location(focused: CGRect(x: 16, y: 300, width: 358, height: 60)).isInsidePage)
        #expect(Self.location(focused: CGRect(x: 16, y: 300, width: 358, height: 60), inHierarchy: true).isInsidePage)
    }

    @Test("focus on the tab bar, navigation bar or back button is outside")
    func chromeIsOutside() {
        #expect(!Self.location(focused: CGRect(x: 0, y: 770, width: 98, height: 49)).isInsidePage, "tab bar")
        #expect(!Self.location(focused: CGRect(x: 8, y: 50, width: 80, height: 44)).isInsidePage, "back button")
    }

    @Test("an element outside the page's hierarchy is outside even over the page")
    func otherHierarchyIsOutside() {
        #expect(!Self.location(focused: CGRect(x: 16, y: 300, width: 358, height: 60), inHierarchy: false).isInsidePage)
    }

    @Test("a covered, off-screen or unfocused page never takes focus")
    func coveredOrHiddenIsOutside() {
        let row = CGRect(x: 16, y: 300, width: 358, height: 60)
        #expect(!Self.location(focused: row, covered: true).isInsidePage, "a sheet holds focus")
        #expect(!Self.location(focused: row, onScreen: false).isInsidePage, "another tab or a covered stack page")
        #expect(!Self.location(focused: nil).isInsidePage, "no VoiceOver cursor (or macOS)")
        #expect(!Self.location(focused: .null).isInsidePage)
    }

    // MARK: Announcements

    @Test("one announcement per publication")
    func announcesOnce() {
        var gate = PublicationRefreshAnnouncements()
        let first = gate.request(for: 1)
        #expect(first)
        let repeated = gate.request(for: 1)
        #expect(!repeated, "a second on-screen page does not repeat it")
        #expect(gate.shouldPost(for: 1))
        let newer = gate.request(for: 2)
        #expect(newer)
        #expect(!gate.shouldPost(for: 1), "a newer publication supersedes a pending one")
    }

    @Test("a page that moved focus to its anchor suppresses the announcement")
    func focusClaimSuppresses() {
        var gate = PublicationRefreshAnnouncements()
        let requested = gate.request(for: 1)
        #expect(requested)
        gate.focusClaimed(for: 1)
        #expect(!gate.shouldPost(for: 1), "claimed after the request: cancelled")
        gate.focusClaimed(for: 2)
        let afterClaim = gate.request(for: 2)
        #expect(!afterClaim, "claimed before the request: never scheduled")
    }
}
