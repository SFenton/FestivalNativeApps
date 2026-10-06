import Testing
@testable import FestivalCore

// MARK: - PublicationRefreshTransition

/// In-place page refresh on a new publication (issue #304, load-transition R3): content
/// out (300 ms) → spinner (150 ms in, ≥400 ms and until prepared for the newest
/// generation) → spinner out (500 ms) → rebuilt content in.
@Suite("PublicationRefreshTransition")
struct PublicationRefreshTransitionTests {
    /// Run a refresh from content to the spinner (content-out finished).
    private static func spinning(from revision: Int = 0, to next: Int = 1) -> PublicationRefreshTransition {
        var transition = PublicationRefreshTransition(revision: revision)
        transition.publicationChanged(to: next)
        transition.timerFired(.contentOut)
        return transition
    }

    @Test("a page starts on its content with nothing to prepare")
    func startsOnContent() {
        let transition = PublicationRefreshTransition(revision: 3)
        #expect(transition.showsContent)
        #expect(!transition.showsSpinner)
        #expect(!transition.isRefreshing)
        #expect(transition.pendingWait == nil)
        #expect(transition.preparationRevision == nil)
        #expect(transition.generation == 0)
    }

    @Test("R3 timings: 300 ms content-out, 150 ms spinner-in, 400 ms hold, 500 ms spinner-out")
    func standardTiming() {
        let timing = PublicationRefreshTransition.Timing.standard(reduceMotion: false)
        #expect(timing.duration(of: .contentOut) == .milliseconds(300))
        #expect(timing.spinnerIn == .milliseconds(150))
        #expect(timing.duration(of: .minimumSpinner) == .milliseconds(400))
        #expect(timing.duration(of: .spinnerOut) == .milliseconds(500))
        #expect(timing.contentOut == ReloadTransition.Timing.contentOutDuration)
        #expect(timing.spinnerOut == ReloadTransition.Timing.spinnerOutDuration)
    }

    @Test("Reduce Motion swaps instantly but keeps the 400 ms hold; frozen fades skip it")
    func reducedTiming() {
        let reduced = PublicationRefreshTransition.Timing.standard(reduceMotion: true)
        #expect(reduced.contentOut == .zero)
        #expect(reduced.spinnerIn == .zero)
        #expect(reduced.spinnerOut == .zero)
        #expect(reduced.minimumSpinner == .milliseconds(400))
        #expect(PublicationRefreshTransition.Timing.instant.minimumSpinner == .zero)
    }

    @Test("content out → spinner → spinner out → rebuilt content")
    func refreshSequence() {
        var transition = PublicationRefreshTransition(revision: 0)
        let changed1 = transition.publicationChanged(to: 1)
        #expect(changed1)
        #expect(transition.phase == .contentOut)
        #expect(!transition.showsContent, "old content is inert and hidden from its fade's start")
        #expect(!transition.showsSpinner)
        #expect(transition.isRefreshing)
        #expect(transition.pendingWait == .contentOut)
        #expect(transition.preparationRevision == nil, "nothing new is drawn while the page fades out")

        transition.timerFired(.contentOut)
        #expect(transition.phase == .spinner)
        #expect(transition.pendingWait == .minimumSpinner)
        #expect(transition.preparationRevision == 1)

        transition.prepared(revision: 1)
        #expect(transition.showsSpinner, "the spinner never blinks: it holds its minimum time")
        #expect(transition.preparationRevision == nil)

        transition.timerFired(.minimumSpinner)
        #expect(transition.phase == .spinnerOut)
        #expect(!transition.showsSpinner, "the spinner fades out")
        #expect(!transition.showsContent, "content waits for the spinner's fade-out")
        #expect(transition.pendingWait == .spinnerOut)
        #expect(transition.generation == 0)

        transition.timerFired(.spinnerOut)
        #expect(transition.showsContent)
        #expect(transition.generation == 1, "the page is rebuilt for the new publication")
        #expect(transition.pendingWait == nil)
    }

    @Test("the spinner stays until preparation finishes")
    func waitsForPreparation() {
        var transition = Self.spinning()
        transition.timerFired(.minimumSpinner)
        #expect(transition.showsSpinner)
        #expect(transition.pendingWait == nil)
        transition.prepared(revision: 1)
        #expect(transition.phase == .spinnerOut)
        transition.timerFired(.spinnerOut)
        #expect(transition.showsContent)
        #expect(transition.generation == 1)
    }

    @Test("stale waits are ignored")
    func staleWaits() {
        var transition = PublicationRefreshTransition(revision: 0)
        transition.publicationChanged(to: 1)
        transition.timerFired(.minimumSpinner)
        transition.timerFired(.spinnerOut)
        #expect(transition.phase == .contentOut)
        transition.timerFired(.contentOut)
        transition.timerFired(.spinnerOut)
        #expect(transition.phase == .spinner)
    }

    @Test("a newer publication during content-out waits for the newer preparation")
    func newerDuringContentOut() {
        var transition = PublicationRefreshTransition(revision: 0)
        transition.publicationChanged(to: 1)
        transition.publicationChanged(to: 2)
        #expect(transition.phase == .contentOut)
        transition.timerFired(.contentOut)
        #expect(transition.preparationRevision == 2)
    }

    @Test("a newer publication during the spinner waits for the newer preparation")
    func newerPublicationWins() {
        var transition = Self.spinning()
        transition.timerFired(.minimumSpinner)
        let changed2 = transition.publicationChanged(to: 2)
        #expect(changed2)
        transition.prepared(revision: 1)
        #expect(transition.showsSpinner, "an older preparation never reveals newer content")
        #expect(transition.preparationRevision == 2)
        transition.prepared(revision: 2)
        transition.timerFired(.spinnerOut)
        #expect(transition.showsContent)
        #expect(transition.generation == 1)
    }

    @Test("a newer publication during spinner-out brings the spinner back")
    func newerDuringSpinnerOut() {
        var transition = Self.spinning()
        transition.prepared(revision: 1)
        transition.timerFired(.minimumSpinner)
        #expect(transition.phase == .spinnerOut)
        transition.publicationChanged(to: 2)
        #expect(transition.showsSpinner)
        #expect(transition.pendingWait == nil, "the hold already ran")
        #expect(transition.preparationRevision == 2)
        transition.timerFired(.spinnerOut)
        #expect(transition.showsSpinner, "the earlier fade-out's timer is stale")
        transition.prepared(revision: 2)
        #expect(transition.phase == .spinnerOut)
        transition.timerFired(.spinnerOut)
        #expect(transition.generation == 1)
    }

    @Test("repeated or older revisions are ignored")
    func ignoresStaleRevisions() {
        var transition = PublicationRefreshTransition(revision: 4)
        let changed4 = transition.publicationChanged(to: 4)
        #expect(!changed4)
        let changed3 = transition.publicationChanged(to: 3)
        #expect(!changed3)
        #expect(transition.showsContent)
        transition.timerFired(.minimumSpinner)
        transition.prepared(revision: 4)
        #expect(transition.generation == 0)
    }

    @Test("each later publication rebuilds the page again")
    func secondRefresh() {
        var transition = Self.spinning()
        transition.prepared(revision: 1)
        transition.timerFired(.minimumSpinner)
        transition.timerFired(.spinnerOut)
        transition.publicationChanged(to: 2)
        #expect(transition.pendingWait == .contentOut)
        transition.timerFired(.contentOut)
        #expect(transition.pendingWait == .minimumSpinner, "a new spinner holds its minimum again")
        transition.prepared(revision: 2)
        transition.timerFired(.minimumSpinner)
        transition.timerFired(.spinnerOut)
        #expect(transition.showsContent)
        #expect(transition.generation == 2)
    }
}
