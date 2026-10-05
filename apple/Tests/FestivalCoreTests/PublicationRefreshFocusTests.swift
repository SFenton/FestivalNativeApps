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
        focus.refreshStarted()
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
        focus.refreshStarted()
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
        focus.refreshStarted()
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: true)
        focus.focusChanged(from: .pageAnchor, to: nil, refreshing: true)
        focus.contentRevealed()
        #expect(!focus.showsAnchor, "the anchor retires instead of pulling focus back")
        #expect(focus.anchorFocusRequest == 1)
    }

    @Test("returning to the anchor during the spinner restores focus after the rebuild")
    func returningDuringRefreshRestores() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted()
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
        focus.refreshStarted()
        focus.focusChanged(from: nil, to: .pageAnchor, refreshing: true)
        focus.contentRevealed()
        focus.focusChanged(from: .pageAnchor, to: nil, refreshing: false)
        #expect(!focus.showsAnchor)
    }

    @Test("a second refresh while the anchor still holds focus focuses it again")
    func secondRefresh() {
        var focus = PublicationRefreshFocus()
        focus.refreshStarted()
        focus.contentRevealed()
        focus.refreshStarted()
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
}
