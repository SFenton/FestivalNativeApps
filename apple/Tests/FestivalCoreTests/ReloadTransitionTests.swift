import Testing
@testable import FestivalCore

// MARK: - ReloadTransition

/// The app-wide load/reload sequence (issue #71): content out → spinner → spinner out →
/// content in, ported from the web `useLoadPhase` / `LoadGate`.
@Suite("ReloadTransition")
struct ReloadTransitionTests {
    @Test("a page that starts loading shows the spinner, then fades it out and shows content")
    func initialLoad() {
        var transition = ReloadTransition(isLoading: true)
        #expect(transition.phase == .spinner)
        #expect(transition.showsSpinner)
        #expect(!transition.showsContent)
        #expect(transition.pendingWait == .minimumSpinner)

        transition.timerFired(.minimumSpinner)
        #expect(transition.phase == .spinner, "still loading: the spinner holds")
        #expect(transition.pendingWait == nil)

        transition.setLoading(false)
        #expect(transition.phase == .spinnerOut)
        #expect(!transition.showsSpinner && !transition.showsContent)
        #expect(transition.pendingWait == .spinnerOut)

        transition.timerFired(.spinnerOut)
        #expect(transition.phase == .content)
        #expect(transition.generation == 1, "new content is rebuilt so its fade plays")
        #expect(transition.pendingWait == nil)
    }

    @Test("a page with data ready shows content at once")
    func readyAtStart() {
        let transition = ReloadTransition(isLoading: false)
        #expect(transition.phase == .content)
        #expect(transition.generation == 0)
        #expect(transition.pendingWait == nil)
    }

    @Test("data that arrives early still waits for the spinner's minimum time")
    func minimumSpinnerHolds() {
        var transition = ReloadTransition(isLoading: true)
        transition.setLoading(false)
        #expect(transition.phase == .spinner)
        #expect(transition.pendingWait == .minimumSpinner)
        transition.timerFired(.minimumSpinner)
        #expect(transition.phase == .spinnerOut)
    }

    @Test("a selection change with synchronous data runs the full sequence")
    func synchronousReload() {
        var transition = ReloadTransition(isLoading: false)
        transition.reload()
        #expect(transition.phase == .spinner, "content fades out as the spinner fades in")
        #expect(transition.pendingWait == .minimumSpinner)
        transition.timerFired(.minimumSpinner)
        #expect(transition.phase == .spinnerOut)
        transition.timerFired(.spinnerOut)
        #expect(transition.phase == .content)
        #expect(transition.generation == 1)
    }

    @Test("a selection change with a network fetch holds the spinner until it finishes")
    func fetchReload() {
        var transition = ReloadTransition(isLoading: false)
        transition.reload()
        transition.setLoading(true)
        transition.timerFired(.minimumSpinner)
        #expect(transition.phase == .spinner)
        transition.setLoading(false)
        #expect(transition.phase == .spinnerOut)
        transition.timerFired(.spinnerOut)
        #expect(transition.phase == .content)
    }

    @Test("loading that starts while content is shown (retry, refetch) is a reload")
    func refetchIsReload() {
        var transition = ReloadTransition(isLoading: false)
        transition.setLoading(true)
        #expect(transition.phase == .spinner)
        #expect(transition.isLoading)
    }

    @Test("a newer choice while the spinner fades out brings it back and never shows stale content")
    func reloadDuringSpinnerOut() {
        var transition = ReloadTransition(isLoading: false)
        transition.reload()
        transition.timerFired(.minimumSpinner)
        #expect(transition.phase == .spinnerOut)

        transition.reload()
        #expect(transition.phase == .spinner)
        #expect(transition.pendingWait == .minimumSpinner)
        transition.timerFired(.spinnerOut)
        #expect(transition.phase == .spinner, "the cancelled fade-out's timer is ignored")
        transition.timerFired(.minimumSpinner)
        transition.timerFired(.spinnerOut)
        #expect(transition.phase == .content)
        #expect(transition.generation == 1)
    }

    @Test("loading that restarts while the spinner fades out brings the spinner back")
    func loadingDuringSpinnerOut() {
        var transition = ReloadTransition(isLoading: false)
        transition.reload()
        transition.timerFired(.minimumSpinner)
        transition.setLoading(true)
        #expect(transition.phase == .spinner)
        transition.timerFired(.minimumSpinner)
        #expect(transition.phase == .spinner)
        transition.setLoading(false)
        #expect(transition.phase == .spinnerOut)
    }

    @Test("repeated choices while the spinner is up keep one spinner and its timer")
    func reloadDuringSpinner() {
        var transition = ReloadTransition(isLoading: false)
        transition.reload()
        let before = transition
        transition.reload()
        #expect(transition == before)
    }

    @Test("stale timers are ignored")
    func staleTimers() {
        var transition = ReloadTransition(isLoading: false)
        transition.timerFired(.minimumSpinner)
        transition.timerFired(.spinnerOut)
        #expect(transition.phase == .content)
        #expect(transition.generation == 0)
    }

    @Test("timing follows web QUICK_FADE_MS / MIN_SPINNER_MS / SPINNER_FADE_MS; Reduce Motion swaps instantly")
    func timing() {
        let motion = ReloadTransition.Timing.standard(reduceMotion: false)
        #expect(motion.spinnerIn == .milliseconds(150))
        #expect(motion.minimumSpinner == .milliseconds(400))
        #expect(motion.spinnerOut == .milliseconds(500))
        #expect(motion.duration(of: .minimumSpinner) == .milliseconds(400))
        #expect(motion.duration(of: .spinnerOut) == .milliseconds(500))

        let reduced = ReloadTransition.Timing.standard(reduceMotion: true)
        #expect(reduced.spinnerIn == .zero)
        #expect(reduced.spinnerOut == .zero)
        #expect(reduced.minimumSpinner == .milliseconds(400), "an instant spinner never blinks")
    }
}
