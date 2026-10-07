import Foundation
import Testing
@testable import FestivalUI

// MARK: - FestivalFadeIn timing

/// Pins the web `fadeInUp` timing port (`FADE_DURATION` 400 ms, `STAGGER_INTERVAL` 125 ms,
/// 12 px rise, first-screen cap) behind `festivalFadeIn(isLoaded:index:)`.
@Test func fadeInMatchesWebConstants() {
    #expect(FestivalFadeIn.duration == 0.4)
    #expect(FestivalFadeIn.staggerInterval == 0.125)
    #expect(FestivalFadeIn.riseDistance == 12)
}

@Test func fadeInStaggerDelaysFirstScreenOnly() {
    // Web `staggerDelay`: (index + 1) × 125 ms.
    #expect(FestivalFadeIn.delay(forIndex: 0) == 0.125)
    #expect(FestivalFadeIn.delay(forIndex: 1) == 0.25)
    #expect(FestivalFadeIn.delay(forIndex: 4) == 0.625)
    #expect(FestivalFadeIn.delay(forIndex: FestivalFadeIn.maxStaggeredItems - 1) != nil)
    #expect(FestivalFadeIn.delay(forIndex: FestivalFadeIn.maxStaggeredItems) == nil)
    #expect(FestivalFadeIn.delay(forIndex: -1) == nil)
    #expect(FestivalFadeIn.delay(forIndex: 3, maxStaggered: 3) == nil)
}

@Test func fadeInCompletionDelayCoversTheLastStaggeredItem() {
    #expect(FestivalFadeIn.completionDelay(itemCount: 0) == 0)
    #expect(abs(FestivalFadeIn.completionDelay(itemCount: 1) - 0.525) < 1e-9)
    #expect(abs(FestivalFadeIn.completionDelay(itemCount: 3) - 0.775) < 1e-9)
    // Items past the cap appear instantly, so they add no time.
    let capped = FestivalFadeIn.completionDelay(itemCount: 100)
    #expect(abs(capped - (Double(FestivalFadeIn.maxStaggeredItems) * 0.125 + 0.4)) < 1e-9)
}

// MARK: - Page scope (issue #30)

/// Only content on screen at page load fades: the scope closes once the content moves.
@MainActor
@Test func fadeScopeStaysOpenUntilTheContentScrolls() {
    let scope = FestivalFadeInScope()
    #expect(scope.isOpen)
    scope.noteContentOffset(0)
    // Sub-threshold layout jitter does not count as a scroll.
    scope.noteContentOffset(FestivalFadeInScope.scrollThreshold)
    scope.noteContentOffset(-FestivalFadeInScope.scrollThreshold)
    #expect(scope.isOpen)
    scope.noteContentOffset(-40)
    #expect(!scope.isOpen)
    // Scrolling back to the resting position never reopens it.
    scope.noteContentOffset(0)
    #expect(!scope.isOpen)
}

@MainActor
@Test func fadeScopeMeasuresFromTheFirstReportedOffset() {
    let scope = FestivalFadeInScope()
    // A non-zero resting offset (content below a bar) is the baseline, not a scroll.
    scope.noteContentOffset(116)
    scope.noteContentOffset(118)
    #expect(scope.isOpen)
    // Pulling down (rubber band / refresh) also counts.
    scope.noteContentOffset(160)
    #expect(!scope.isOpen)
}

@MainActor
@Test func fadeScopeIgnoresNonFiniteOffsetsAndClosesExplicitly() {
    let scope = FestivalFadeInScope()
    scope.noteContentOffset(.nan)
    scope.noteContentOffset(.infinity)
    scope.noteContentOffset(10)
    #expect(scope.isOpen)
    scope.close()
    #expect(!scope.isOpen)
}

// MARK: - Settled stagger and appending feeds

@Test func fadeStaggerPassesNoIndexOnceSettled() {
    #expect(FadeStagger.index(3, settled: false) == 3)
    #expect(FadeStagger.index(3, settled: true) == -1)
    #expect(FestivalFadeIn.delay(forIndex: FadeStagger.index(0, settled: true)) == nil)
}

@Test func fadeBatchIndexesStaggerOnlyTheNewestBatchInDisplayOrder() {
    let order = ["a", "b", "c", "d", "e"]
    // Earlier pages (a, b) never fade; the new page staggers from 0 in display order,
    // skipping items a filter hides (c is filtered out of `order` here by omission).
    let indexes = FadeStagger.batchIndexes(
        order: order.filter { $0 != "c" }, batch: ["c", "d", "e"], settled: false
    )
    #expect(indexes == ["d": 0, "e": 1])
    #expect(indexes["a"] == nil)
    // Once the batch has settled, rows rebuilt by scrolling appear without a fade.
    #expect(FadeStagger.batchIndexes(order: order, batch: ["d", "e"], settled: true).isEmpty)
    // Duplicate IDs keep their first position.
    #expect(FadeStagger.batchIndexes(order: ["x", "x", "y"], batch: ["x", "y"], settled: false) == ["x": 0, "y": 1])
}

// MARK: - Stagger rush (issue #323)

/// A settable clock for scope tests.
@MainActor
private final class FakeClock {
    var time: TimeInterval = 100
}

@Test func fadeInStartClassifiesStaggeredPastFirstScreenAndNever() {
    #expect(FestivalFadeIn.start(forIndex: 0) == .after(0.125))
    #expect(FestivalFadeIn.start(forIndex: FestivalFadeIn.maxStaggeredItems - 1) == .after(1.0))
    #expect(FestivalFadeIn.start(forIndex: FestivalFadeIn.maxStaggeredItems) == .pastFirstScreen)
    #expect(FestivalFadeIn.start(forIndex: Int.max) == .pastFirstScreen)
    #expect(FestivalFadeIn.start(forIndex: -1) == .never)
}

@Test func fadeInEntranceEndWaitsForTheRowOrTheStaggerTail() {
    #expect(abs(FestivalFadeIn.entranceEnd(forIndex: nil) - 0.4) < 1e-9)
    #expect(abs(FestivalFadeIn.entranceEnd(forIndex: 0) - 0.525) < 1e-9)
    #expect(abs(FestivalFadeIn.entranceEnd(forIndex: 3) - 0.9) < 1e-9)
    // Past the first screen a row ends with the last staggered one.
    #expect(abs(FestivalFadeIn.entranceEnd(forIndex: 20) - 1.4) < 1e-9)
    #expect(abs(FestivalFadeIn.entranceEnd(forIndex: -5) - 0.525) < 1e-9)
}

/// Open scope: staggered rows keep their delay; rows past the first screen fade with the
/// last staggered row (measured from the scope's first fade), never before it.
@MainActor
@Test func fadeScopeSchedulesPastFirstScreenRowsWithTheStaggerTail() {
    let clock = FakeClock()
    let scope = FestivalFadeInScope(now: { clock.time })
    #expect(scope.scheduleFade(.after(0.25)) == 0.25)
    #expect(scope.scheduleFade(.after(0)) == 0)
    #expect(scope.scheduleFade(.never) == nil)
    #expect(scope.scheduleFade(.pastFirstScreen) == 1.0)
    clock.time += 0.6
    let tail = scope.scheduleFade(.pastFirstScreen) ?? -1
    #expect(abs(tail - 0.4) < 1e-9)
    clock.time += 5
    #expect(scope.scheduleFade(.pastFirstScreen) == 0)
}

/// Web `useStaggerRush`: a scroll during the first load makes every pending fade, and every
/// row built in the next fade duration, start at once; after that rows appear plainly.
@MainActor
@Test func fadeScopeRushesPendingFadesOnTheFirstScroll() {
    let clock = FakeClock()
    let scope = FestivalFadeInScope(now: { clock.time })
    scope.noteContentOffset(0)
    _ = scope.scheduleFade(.after(1.0))
    clock.time += 0.2
    scope.noteContentOffset(-200)
    #expect(scope.isRushed)
    #expect(scope.hasScrolled)
    #expect(scope.isOpen)
    // Rows the scroll reaches fade in together, immediately.
    #expect(scope.scheduleFade(.after(0.75)) == 0)
    #expect(scope.scheduleFade(.pastFirstScreen) == 0)
    #expect(scope.scheduleFade(.never) == nil)
    // Once the rushed fades are done, nothing replays (load-transition R5).
    clock.time += FestivalFadeIn.duration
    #expect(!scope.isOpen)
    #expect(scope.scheduleFade(.after(0.125)) == nil)
    #expect(scope.scheduleFade(.pastFirstScreen) == nil)
    // Later scrolls change nothing.
    scope.noteContentOffset(-900)
    #expect(!scope.isOpen)
}

/// The page's frozen time (`festivalFadeInFrozenTime`, issue #327) times the scope while
/// it is set: the rush window stays open however long the host stalls; nil restores the
/// scope's own clock.
@MainActor
@Test func fadeScopeUsesThePagesFrozenTime() {
    let clock = FakeClock()
    let scope = FestivalFadeInScope(now: { clock.time })
    scope.freezeClock(at: clock.time)
    scope.noteContentOffset(0)
    _ = scope.scheduleFade(.after(1.0))
    scope.noteContentOffset(-200)
    #expect(scope.isRushed)
    clock.time += 60
    #expect(scope.isOpen)
    #expect(scope.scheduleFade(.pastFirstScreen) == 0)
    scope.freezeClock(at: nil)
    #expect(!scope.isOpen)
    #expect(scope.scheduleFade(.pastFirstScreen) == nil)
}

/// A scroll after every fade has finished closes the window without a rush.
@MainActor
@Test func fadeScopeClosesWhenScrolledAfterTheFadesFinished() {
    let clock = FakeClock()
    let scope = FestivalFadeInScope(now: { clock.time })
    scope.noteContentOffset(0)
    _ = scope.scheduleFade(.after(0.125))
    clock.time += 0.6
    scope.noteContentOffset(-50)
    #expect(!scope.isRushed)
    #expect(!scope.isOpen)
    #expect(scope.scheduleFade(.after(0.125)) == nil)
}

/// A reset key re-arms the window for a new set of rows (web `resetRush`): the current
/// position becomes the resting one, and the new rows stagger again.
@MainActor
@Test func fadeScopeReArmsForANewResetKeyOnly() {
    let clock = FakeClock()
    let scope = FestivalFadeInScope(now: { clock.time })
    scope.arm(for: AnyHashable("page-1"))
    scope.noteContentOffset(0)
    scope.noteContentOffset(-300)
    #expect(!scope.isOpen)
    scope.arm(for: AnyHashable("page-1"))
    #expect(!scope.isOpen)
    scope.arm(for: AnyHashable("page-2"))
    #expect(scope.isOpen)
    #expect(!scope.hasScrolled)
    // Resting at the scrolled position: small jitter there is not a scroll.
    scope.noteContentOffset(-302)
    #expect(scope.isOpen)
    #expect(scope.scheduleFade(.after(0.5)) == 0.5)
    scope.noteContentOffset(-360)
    #expect(scope.isRushed)
}

/// A fade waiting for its stagger delay starts as soon as a scroll rushes the page.
@MainActor
@Test func fadeScopeReleasesWaitingFadesOnARush() async {
    let scope = FestivalFadeInScope()
    // An hour-long stagger: a released waiter returns long before it, even when the
    // parallel hosted suites starve the main actor for tens of seconds.
    let delay = scope.scheduleFade(.after(3600)) ?? 0
    let started = ProcessInfo.processInfo.systemUptime
    let waiter = Task { @MainActor in
        await scope.waitToStart(after: delay)
        return ProcessInfo.processInfo.systemUptime - started
    }
    try? await Task.sleep(for: .milliseconds(50))
    scope.rush()
    let waited = await waiter.value
    #expect(waited < 600)
    // Already rushed: no wait at all.
    await scope.waitToStart(after: 3600)
}

@MainActor
@Test func fadeScopeWaitEndsWithItsDelayOrCancellation() async {
    let scope = FestivalFadeInScope()
    _ = scope.scheduleFade(.after(0.05))
    await scope.waitToStart(after: 0.05)
    let cancelled = Task { @MainActor in await scope.waitToStart(after: 30) }
    try? await Task.sleep(for: .milliseconds(20))
    cancelled.cancel()
    await cancelled.value
    #expect(scope.isOpen)
}

/// Review of #351: the reveal of a row past the first screen starts exactly as the stagger
/// ends (index ≥ 8 waits 1.4 s). A plain scroll then closes the finished scope, so the
/// rows it reaches would appear opaque; the reveal's own scroll opens a rush window for
/// the scroll plus one fade instead.
@MainActor
@Test func fadeScopeAutomaticScrollAfterTheStaggerFadesTheRowsItReaches() {
    let clock = FakeClock()
    let plain = FestivalFadeInScope(now: { clock.time })
    let revealed = FestivalFadeInScope(now: { clock.time })
    for scope in [plain, revealed] {
        scope.noteContentOffset(0)
        _ = scope.scheduleFade(.after(0.125))
        #expect(scope.scheduleFade(.pastFirstScreen) == 1.0)
    }
    clock.time += FestivalFadeIn.entranceEnd(forIndex: 19)
    // Without the reveal's preparation: the scroll closes the window (the bug).
    plain.noteContentOffset(-600)
    #expect(!plain.isOpen)
    #expect(plain.scheduleFade(.pastFirstScreen) == nil)
    // With it: rows the scroll realizes fade at once, for the scroll plus one fade.
    revealed.prepareForAutomaticScroll(lasting: SelectedRowReveal.scrollDuration)
    #expect(revealed.isRushed)
    revealed.noteContentOffset(-600)
    #expect(revealed.isOpen)
    #expect(revealed.scheduleFade(.pastFirstScreen) == 0)
    clock.time += SelectedRowReveal.scrollDuration + FestivalFadeIn.duration - 0.01
    #expect(revealed.scheduleFade(.pastFirstScreen) == 0)
    // Then nothing replays (load-transition R5).
    clock.time += 0.02
    #expect(!revealed.isOpen)
    #expect(revealed.scheduleFade(.pastFirstScreen) == nil)
    // A reset restores the ordinary rush window.
    revealed.reset()
    revealed.noteContentOffset(-600)
    _ = revealed.scheduleFade(.after(1.0))
    revealed.noteContentOffset(-700)
    clock.time += FestivalFadeIn.duration + 0.01
    #expect(!revealed.isOpen)
}

/// With entrances still waiting, the reveal leaves the rush to its scroll's movement, as
/// any scroll (one that does not move keeps the stagger running).
@MainActor
@Test func fadeScopeAutomaticScrollRushesWaitingFadesOnlyWhenItMoves() async {
    let scope = FestivalFadeInScope()
    scope.noteContentOffset(0)
    let delay = scope.scheduleFade(.after(3600)) ?? 0
    let waiter = Task { @MainActor in await scope.waitToStart(after: delay) }
    try? await Task.sleep(for: .milliseconds(50))
    scope.prepareForAutomaticScroll(lasting: SelectedRowReveal.scrollDuration)
    #expect(!scope.isRushed)
    scope.noteContentOffset(-300)
    #expect(scope.isRushed)
    await waiter.value
    // Once rushed, a later preparation changes nothing.
    scope.prepareForAutomaticScroll(lasting: 10)
    #expect(scope.isRushed)
}

/// Records when a waiting fade was let start.
@MainActor
private final class StartFlag {
    var started = false
}

/// While a selected-row scroll is expected, a row past the first screen whose turn comes
/// (a lazy list builds rows just below the viewport early) waits for that scroll to rush
/// it, so the row the scroll reaches has not spent its entrance unseen; staggered rows
/// keep their schedule.
@MainActor
@Test func fadeScopeHoldsRowsPastTheFirstScreenForTheExpectedScroll() async {
    let scope = FestivalFadeInScope()
    let token = scope.expectAutomaticScroll()
    #expect(token != nil)
    #expect(scope.holds(.pastFirstScreen))
    #expect(!scope.holds(.after(0)))
    #expect(!scope.holds(.never))
    let tail = StartFlag()
    let late = StartFlag()
    let staggered = StartFlag()
    let tailTask = Task { @MainActor in
        await scope.waitToStart(after: 0.05, start: .pastFirstScreen)
        tail.started = true
    }
    // Built after the stagger: no delay left, still held.
    let lateTask = Task { @MainActor in
        await scope.waitToStart(after: 0, start: .pastFirstScreen)
        late.started = true
    }
    let staggeredTask = Task { @MainActor in
        await scope.waitToStart(after: 0.05, start: .after(0.05))
        staggered.started = true
    }
    await staggeredTask.value
    #expect(staggered.started)
    try? await Task.sleep(for: .milliseconds(300))
    #expect(!tail.started)
    #expect(!late.started)
    // The scroll starts: everything held fades now, together.
    scope.prepareForAutomaticScroll(lasting: SelectedRowReveal.scrollDuration)
    await tailTask.value
    await lateTask.value
    #expect(scope.isRushed)
    #expect(!scope.holds(.pastFirstScreen))
    #expect(scope.expectAutomaticScroll() == nil)
}

/// A reveal called off (cancelled, or the reader scrolled first) lets held rows fade on
/// their own; a stale token or a reset never strands one.
@MainActor
@Test func fadeScopeReleasesHeldRowsWhenTheScrollIsCalledOff() async {
    let scope = FestivalFadeInScope()
    scope.arm(for: AnyHashable("page-1"))
    let stale = scope.expectAutomaticScroll()
    scope.arm(for: AnyHashable("page-2"))
    #expect(!scope.holds(.pastFirstScreen))
    let token = scope.expectAutomaticScroll()
    let held = Task { @MainActor in await scope.waitToStart(after: 0, start: .pastFirstScreen) }
    try? await Task.sleep(for: .milliseconds(50))
    scope.endAutomaticScrollExpectation(stale)
    scope.endAutomaticScrollExpectation(nil)
    #expect(scope.holds(.pastFirstScreen))
    scope.endAutomaticScrollExpectation(token)
    await held.value
    #expect(!scope.isRushed)
    #expect(scope.isOpen)
    #expect(!scope.holds(.pastFirstScreen))
}

/// A selected-row scroll waits while a reload gate's animated reveal is still growing the
/// page's scroll content (issue #327): a scroll issued then stopped at the content's end of
/// the moment and stayed there. Nested reveals all have to end, and the reveal's own
/// re-arm of the scope doesn't forget them.
@MainActor
@Test func fadeScopeAutomaticScrollWaitsForTheContentReveal() async {
    let scope = FestivalFadeInScope()
    // Nothing growing: no wait.
    await scope.contentRevealed()
    #expect(!scope.isRevealingContent)
    // An extra end never leaves a negative count behind.
    scope.endContentReveal()
    scope.beginContentReveal()
    scope.beginContentReveal()
    #expect(scope.isRevealingContent)
    let scrolled = StartFlag()
    let reveal = Task { @MainActor in
        await scope.contentRevealed()
        scrolled.started = true
    }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!scrolled.started)
    // The gate's reveal re-arms the scope for its rows in the same update.
    scope.arm(for: AnyHashable("page-2"))
    scope.endContentReveal()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!scrolled.started)
    #expect(scope.isRevealingContent)
    scope.endContentReveal()
    await reveal.value
    #expect(scrolled.started)
    #expect(!scope.isRevealingContent)
}

/// A selected-row reveal cancelled while it waits for the content (the page went or
/// reloaded) stops waiting rather than holding its task.
@MainActor
@Test func fadeScopeContentRevealWaitEndsOnCancellation() async {
    let scope = FestivalFadeInScope()
    scope.beginContentReveal()
    let reveal = Task { @MainActor in await scope.contentRevealed() }
    try? await Task.sleep(for: .milliseconds(50))
    reveal.cancel()
    await reveal.value
    #expect(scope.isRevealingContent)
    // A later wait still sees the running reveal end.
    let next = Task { @MainActor in await scope.contentRevealed() }
    try? await Task.sleep(for: .milliseconds(50))
    scope.endContentReveal()
    await next.value
    #expect(!scope.isRevealingContent)
}

// MARK: - Selected-row reveal wait (issue #323)

@MainActor
@Test func selectedRowRevealWaitsForTheRowEntrance() {
    // Web `navToPlayer`: wait for the row's own entrance before scrolling.
    #expect(SelectedRowReveal.wait(staggerIndex: 0, animates: true) == .milliseconds(525))
    #expect(SelectedRowReveal.wait(staggerIndex: 5, animates: true) == .milliseconds(1150))
    #expect(SelectedRowReveal.wait(staggerIndex: 24, animates: true) == .milliseconds(1400))
    // A block-fade page waits for its one fade.
    #expect(SelectedRowReveal.wait(staggerIndex: nil, animates: true) == .milliseconds(400))
    // Reduce Motion or fades off: only the layout settle (R6).
    #expect(SelectedRowReveal.wait(staggerIndex: 24, animates: false) == SelectedRowReveal.settle)
}

@MainActor
@Test func songsRowsPastTheFirstScreenFadeOnlyDuringTheReveal() {
    let order = ["a": 0, "b": 1]
    #expect(SongsScreen.fadeIndex("a", in: order) == 0)
    // Rows a scroll or section jump reaches during the reveal fade with the rest.
    #expect(SongsScreen.fadeIndex("z", in: order) == FestivalFadeIn.maxStaggeredItems)
    // After the reveal every row takes the plain path.
    #expect(SongsScreen.fadeIndex("a", in: [:]) == nil)
}
