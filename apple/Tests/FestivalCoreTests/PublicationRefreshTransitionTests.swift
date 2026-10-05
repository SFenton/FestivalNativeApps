import Testing
@testable import FestivalCore

// MARK: - PublicationRefreshTransition

/// In-place page refresh on a new publication (issue #304): content out → spinner (≥400 ms
/// and until prepared for the newest generation) → rebuilt content in.
@Suite("PublicationRefreshTransition")
struct PublicationRefreshTransitionTests {
    @Test("a page starts on its content with nothing to prepare")
    func startsOnContent() {
        let transition = PublicationRefreshTransition(revision: 3)
        #expect(transition.showsContent)
        #expect(!transition.showsSpinner)
        #expect(transition.pendingWait == nil)
        #expect(transition.preparationRevision == nil)
        #expect(transition.generation == 0)
    }

    @Test("a new publication shows the spinner, then rebuilds after the hold and preparation")
    func refreshSequence() {
        var transition = PublicationRefreshTransition(revision: 0)
        let changed1 = transition.publicationChanged(to: 1)
        #expect(changed1)
        #expect(transition.showsSpinner)
        #expect(transition.pendingWait == .minimumSpinner)
        #expect(transition.preparationRevision == 1)

        transition.prepared(revision: 1)
        #expect(transition.showsSpinner, "the spinner never blinks: it holds its minimum time")
        #expect(transition.preparationRevision == nil)

        transition.minimumSpinnerElapsed()
        #expect(transition.showsContent)
        #expect(transition.generation == 1, "the page is rebuilt for the new publication")
        #expect(transition.pendingWait == nil)
    }

    @Test("the spinner stays until preparation finishes")
    func waitsForPreparation() {
        var transition = PublicationRefreshTransition(revision: 0)
        transition.publicationChanged(to: 1)
        transition.minimumSpinnerElapsed()
        #expect(transition.showsSpinner)
        #expect(transition.pendingWait == nil)
        transition.prepared(revision: 1)
        #expect(transition.showsContent)
        #expect(transition.generation == 1)
    }

    @Test("a newer publication during the spinner waits for the newer preparation")
    func newerPublicationWins() {
        var transition = PublicationRefreshTransition(revision: 0)
        transition.publicationChanged(to: 1)
        transition.minimumSpinnerElapsed()
        let changed2 = transition.publicationChanged(to: 2)
        #expect(changed2)
        transition.prepared(revision: 1)
        #expect(transition.showsSpinner, "an older preparation never reveals newer content")
        #expect(transition.preparationRevision == 2)
        transition.prepared(revision: 2)
        #expect(transition.showsContent)
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
        transition.minimumSpinnerElapsed()
        transition.prepared(revision: 4)
        #expect(transition.generation == 0)
    }

    @Test("each later publication rebuilds the page again")
    func secondRefresh() {
        var transition = PublicationRefreshTransition(revision: 0)
        transition.publicationChanged(to: 1)
        transition.prepared(revision: 1)
        transition.minimumSpinnerElapsed()
        transition.publicationChanged(to: 2)
        #expect(transition.showsSpinner)
        #expect(transition.pendingWait == .minimumSpinner, "a new spinner holds its minimum again")
        transition.prepared(revision: 2)
        transition.minimumSpinnerElapsed()
        #expect(transition.showsContent)
        #expect(transition.generation == 2)
    }
}
