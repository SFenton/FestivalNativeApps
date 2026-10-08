import CoreFoundation
import Foundation
import Observation
import Testing
@testable import FestivalUI

/// Issue #8: scroll-driven Songs chrome must not invalidate anything for writes that do
/// not change a value, and must notify its observers for real changes.
@MainActor
struct SongsScrollChromeTests {
    /// Runs `write` and reports whether an observer of `read` was invalidated.
    private func invalidates(
        _ chrome: SongsScrollChrome, reading read: @escaping (SongsScrollChrome) -> Void,
        by write: (SongsScrollChrome) -> Void
    ) -> Bool {
        let fired = Flag()
        withObservationTracking { read(chrome) } onChange: { fired.value = true }
        write(chrome)
        return fired.value
    }

    /// Set synchronously by `onChange` during the write on the main actor.
    private final class Flag: @unchecked Sendable {
        var value = false
    }

    @Test func scrolledWritesOnlyOnChange() {
        let chrome = SongsScrollChrome()
        #expect(!chrome.setScrolled(false))
        #expect(!invalidates(chrome, reading: { _ = $0.listScrolled }) { $0.setScrolled(false) })
        #expect(invalidates(chrome, reading: { _ = $0.listScrolled }) { $0.setScrolled(true) })
        #expect(chrome.listScrolled)
        #expect(!chrome.setScrolled(true))
        #expect(chrome.setScrolled(false))
    }

    /// Issue #297: a long animated scroll to the top skips titles that never report
    /// leaving the bar, so reaching the top forgets them all (built titles re-assert).
    @Test func returningToTheTopForgetsPassedTitles() {
        let chrome = SongsScrollChrome()
        let keys = ["#", "A", "B", "M"]
        chrome.setScrolled(true)
        chrome.setHeader("#", passed: true)
        chrome.setHeader("M", passed: true)
        // Leaving the top keeps what the titles reported.
        #expect(chrome.passedHeaders == ["#", "M"])
        #expect(invalidates(chrome, reading: { _ = $0.passedHeaders }) { $0.setScrolled(false) })
        #expect(chrome.passedHeaders.isEmpty)
        #expect(chrome.currentSectionIndex(in: keys) == 0)
        // The first title, still built at the top, re-asserts its answer.
        chrome.setHeader("#", passed: true)
        chrome.setScrolled(true)
        #expect(chrome.passedHeaders == ["#"])
        #expect(chrome.currentSectionIndex(in: keys) == 0)
    }

    @Test func headerWritesOnlyOnChange() {
        let chrome = SongsScrollChrome()
        #expect(!invalidates(chrome, reading: { _ = $0.passedHeaders }) {
            $0.setHeader("A", passed: false)
        })
        #expect(invalidates(chrome, reading: { _ = $0.passedHeaders }) {
            $0.setHeader("A", passed: true)
        })
        // Geometry callbacks repeat the same answer every frame while a title stays put.
        #expect(!invalidates(chrome, reading: { _ = $0.passedHeaders }) {
            $0.setHeader("A", passed: true)
        })
        #expect(chrome.passedHeaders == ["A"])
        #expect(chrome.setHeader("A", passed: false))
        #expect(chrome.passedHeaders.isEmpty)
    }

    @Test func resetHeadersOnlyWhenSomePassed() {
        let chrome = SongsScrollChrome()
        #expect(!invalidates(chrome, reading: { _ = $0.passedHeaders }) { $0.resetHeaders() })
        chrome.setHeader("A", passed: true)
        chrome.setHeader("B", passed: true)
        #expect(invalidates(chrome, reading: { _ = $0.passedHeaders }) { $0.resetHeaders() })
        #expect(chrome.passedHeaders.isEmpty)
    }

    @Test func sectionBarBottomIgnoresSubPointJitterAndNonFinite() {
        let chrome = SongsScrollChrome()
        #expect(invalidates(chrome, reading: { _ = $0.sectionBarBottom }) {
            $0.setSectionBarBottom(120)
        })
        #expect(!invalidates(chrome, reading: { _ = $0.sectionBarBottom }) {
            $0.setSectionBarBottom(120.3)
        })
        #expect(!chrome.setSectionBarBottom(.nan))
        #expect(!chrome.setSectionBarBottom(.infinity))
        #expect(chrome.sectionBarBottom == 120)
        #expect(chrome.setSectionBarBottom(120 + SongsScrollChrome.barBottomTolerance))
    }

    /// Writes to one property never invalidate observers of another (the List reads none).
    @Test func propertiesAreObservedIndependently() {
        let chrome = SongsScrollChrome()
        #expect(!invalidates(chrome, reading: { _ = $0.listScrolled }) {
            $0.setHeader("A", passed: true)
            $0.setSectionBarBottom(90)
        })
    }

    @Test func currentSectionIsLastPassedInListOrder() {
        let chrome = SongsScrollChrome()
        let keys = ["#", "A", "B", "C"]
        #expect(chrome.currentSectionIndex(in: []) == nil)
        #expect(chrome.currentSectionIndex(in: keys) == 0)
        chrome.setHeader("B", passed: true)
        chrome.setHeader("A", passed: true)
        #expect(chrome.currentSectionIndex(in: keys) == 2)
        // A stale key from an earlier sort does not match.
        chrome.setHeader("Z", passed: true)
        #expect(chrome.currentSectionIndex(in: keys) == 2)
        chrome.resetHeaders()
        #expect(chrome.currentSectionIndex(in: keys) == 0)
    }

    // MARK: - Section push (issue #288)

    /// The landing line (flush with the bar since issue #298) and bar title height.
    private let landing = SongsScrollChrome.landingOffset
    private let bar: CGFloat = 32

    @Test func pushBandStartsBelowTheLandingLineByOneBarHeight() {
        let band = landing + bar
        #expect(SongsScrollChrome.pushBandTop(titleTop: band + 0.5, landingOffset: landing, barHeight: bar) == nil)
        #expect(SongsScrollChrome.pushBandTop(titleTop: band, landingOffset: landing, barHeight: bar) == band)
        #expect(SongsScrollChrome.pushBandTop(titleTop: 12, landingOffset: landing, barHeight: bar) == 12)
        // Far above the bar it clamps, so pinned titles stop reporting every frame.
        let floor = -(SongsScrollChrome.titleAlignment + 1)
        #expect(SongsScrollChrome.pushBandTop(titleTop: -400, landingOffset: landing, barHeight: bar) == floor)
        #expect(SongsScrollChrome.pushBandTop(titleTop: .nan, landingOffset: landing, barHeight: bar) == nil)
        // A negative bar height counts as none: the band ends at the landing line.
        #expect(SongsScrollChrome.pushBandTop(titleTop: landing + 0.5, landingOffset: landing, barHeight: -5) == nil)
        #expect(SongsScrollChrome.pushBandTop(titleTop: landing - 0.5, landingOffset: landing, barHeight: -5) == landing - 0.5)
    }

    private func layout(
        current: CGFloat?, passed: Bool = false, next: CGFloat?
    ) -> SongsScrollChrome.SectionBarLayout {
        SongsScrollChrome.sectionBarLayout(
            currentTop: current, currentPassed: passed, nextTop: next,
            landingOffset: landing, barHeight: bar
        )
    }

    @Test func currentTitleRidesItsRowThenPins() {
        let a = SongsScrollChrome.titleAlignment
        #expect(layout(current: nil, next: nil) == .init(currentY: nil, nextY: nil))
        #expect(layout(current: nil, passed: true, next: nil) == .init(currentY: 0, nextY: nil))
        #expect(layout(current: 20, passed: true, next: nil) == .init(currentY: 20 + a, nextY: nil))
        #expect(layout(current: -a - 1, passed: true, next: nil) == .init(currentY: 0, nextY: nil))
    }

    @Test func incomingTitlePushesThePinnedOneOut() {
        let a = SongsScrollChrome.titleAlignment
        // Entering the band: drawn at its row, the pinned title not yet moved.
        #expect(layout(current: nil, passed: true, next: landing + bar) ==
            .init(currentY: 0, nextY: landing + bar + a))
        // Halfway: the pinned title moved up 1:1 with the scroll.
        #expect(layout(current: nil, passed: true, next: landing + 16) ==
            .init(currentY: -16, nextY: landing + 16 + a))
        // At the landing line (where it becomes current and where jumps land) it is gone.
        #expect(layout(current: nil, passed: true, next: landing).currentY == nil)
        #expect(layout(current: nil, passed: true, next: landing + 0.5).currentY == -bar + 0.5)
    }

    @Test func pushIsContinuousAcrossTheBand() {
        var previous: SongsScrollChrome.SectionBarLayout?
        for step in stride(from: landing + bar + 4, through: landing - 4, by: -0.5) {
            let top = SongsScrollChrome.pushBandTop(titleTop: step, landingOffset: landing, barHeight: bar)
            let now = layout(current: nil, passed: true, next: top)
            if let previous, let was = previous.currentY, let is_ = now.currentY {
                #expect(abs(was - is_) <= 0.5)
            }
            if let was = previous?.nextY, let is_ = now.nextY {
                #expect(abs(was - is_) <= 0.5)
            }
            previous = now
        }
    }

    private func previousY(current: CGFloat?) -> CGFloat? {
        SongsScrollChrome.previousTitleY(currentTop: current, landingOffset: landing, barHeight: bar)
    }

    /// Issue #297: once the current title's row has left the band (scrolled far above the
    /// bar, dismantled by the List, or never built after a jump), the previous section's
    /// title must not stay pinned underneath the current one.
    @Test func previousTitleIsGoneOnceTheCurrentTitleLeftTheBand() {
        #expect(previousY(current: nil) == nil)
        #expect(previousY(current: .nan) == nil)
        // Clamped far above the bar: pushed out long ago.
        #expect(previousY(current: -(SongsScrollChrome.titleAlignment + 1)) == nil)
        // On or above the landing line the current title has pushed it fully out.
        #expect(previousY(current: landing) == nil)
        #expect(previousY(current: landing - 4) == nil)
    }

    @Test func previousTitleFollowsTheTitlePushingItOut() {
        // Just past the landing line (the passed check's tolerance) it is still leaving.
        #expect(previousY(current: landing + 0.5) == -bar + 0.5)
        #expect(previousY(current: landing + 16) == -16)
        // Never drawn below the bar's top: pinned at most.
        #expect(previousY(current: landing + bar) == 0)
        #expect(previousY(current: landing + bar + 10) == 0)
    }

    /// The bar's previous and current titles never share the pinned slot: with no band top
    /// for the current title the current one is pinned and the previous one is gone.
    @Test func currentAndPreviousTitlesNeverOverlapWhilePinned() {
        let pinned = layout(current: nil, passed: true, next: nil)
        #expect(pinned.currentY == 0)
        #expect(previousY(current: nil) == nil)
        // While the current title is pushing, the two sit one bar height apart at most.
        for step in stride(from: landing + bar, through: landing, by: -1) {
            let current = layout(current: step, passed: true, next: nil).currentY
            if let current, let previous = previousY(current: step) {
                #expect(current - previous >= bar - SongsScrollChrome.titleAlignment - 0.001)
            }
        }
    }

    @Test func titleTopsWriteOnlyOnChange() {
        let chrome = SongsScrollChrome()
        #expect(invalidates(chrome, reading: { _ = $0.titleTops }) { $0.setTitleTop("A", top: 40) })
        #expect(!invalidates(chrome, reading: { _ = $0.titleTops }) { $0.setTitleTop("A", top: 40.05) })
        // A non-finite top counts as leaving the band.
        #expect(chrome.setTitleTop("A", top: .nan))
        #expect(chrome.titleTops["A"] == nil)
        #expect(!chrome.setTitleTop("B", top: nil))
        #expect(chrome.setTitleTop("B", top: 3))
        #expect(chrome.setTitleTop("B", top: nil))
        #expect(chrome.titleTops["B"] == nil)
        #expect(!invalidates(chrome, reading: { _ = $0.listScrolled }) { $0.setTitleTop("C", top: 1) })
    }

    @Test func barMetricsSetTheMaskEdge() {
        let chrome = SongsScrollChrome()
        chrome.setBarMetrics(top: 100, height: 0)
        #expect(chrome.barTop.value == 100)
        #expect(chrome.barHeight.value == 0)
        #expect(chrome.sectionBarBottom == 0)
        chrome.setBarMetrics(top: 100, height: 32)
        #expect(chrome.barHeight.value == 32)
        #expect(chrome.sectionBarBottom == 132)
        chrome.setBarMetrics(top: .nan, height: .infinity)
        #expect(chrome.barTop.value == 100)
        #expect(chrome.sectionBarBottom == 132)
    }
}

/// Issue #9: an instant A–Z rail or Quick Links jump names its target in the section bar,
/// whatever the in-list titles reported before it.
@MainActor
struct SongsSectionJumpTests {
    /// Rail order: `#`, then A–Z, keyed like `SongsScreen.headerKey` (position ids).
    private let keys = (0..<27).map { SongsScreen.headerKey(AnyHashable($0)) }

    @Test func railKeysMatchTheInListTitleKeys() {
        #expect(SongsScreen.headerKey(AnyHashable(16)) == "16")
        #expect(SongsScreen.headerKey(AnyHashable("year:1990")) == "year:1990")
    }

    @Test func farJumpFromTheTopNamesTheTarget() {
        let chrome = SongsScrollChrome()
        // Before the jump only "#" had reached the bar; "A" and "B" were on screen.
        chrome.setHeader(keys[0], passed: true)
        #expect(chrome.jump(to: keys[16], in: keys))
        #expect(chrome.currentSectionIndex(in: keys) == 16)
        // The titles that were on screen report passing as the list moves away.
        chrome.setHeader(keys[1], passed: true)
        chrome.setHeader(keys[2], passed: true)
        #expect(chrome.currentSectionIndex(in: keys) == 16)
    }

    @Test func jumpBackClearsTitlesPassedBeyondTheTarget() {
        let chrome = SongsScrollChrome()
        chrome.jump(to: keys[16], in: keys)
        // "Q" scrolled past the bar on a later jump and was then dismantled: it never
        // reports again, which left the bar reading "Q" over the A rows.
        chrome.setHeader(keys[17], passed: true)
        chrome.jump(to: keys[22], in: keys)
        chrome.jump(to: keys[1], in: keys)
        #expect(chrome.currentSectionIndex(in: keys) == 1)
        #expect(chrome.passedHeaders == Set(keys[...1]))
    }

    @Test func jumpToTheFirstSectionKeepsOnlyIt() {
        let chrome = SongsScrollChrome()
        chrome.jump(to: keys[26], in: keys)
        #expect(chrome.jump(to: keys[0], in: keys))
        #expect(chrome.passedHeaders == [keys[0]])
        #expect(chrome.currentSectionIndex(in: keys) == 0)
    }

    @Test func repeatJumpNotifiesNoOneButAdvancesTheGeneration() {
        let chrome = SongsScrollChrome()
        chrome.jump(to: keys[5], in: keys)
        let generation = chrome.jumpGeneration
        let fired = JumpFlag()
        withObservationTracking { _ = chrome.passedHeaders } onChange: { fired.value = true }
        #expect(!chrome.jump(to: keys[5], in: keys))
        #expect(!fired.value)
        // A corrective scroll scheduled by the earlier jump must stand down.
        #expect(chrome.jumpGeneration == generation + 1)
    }

    @Test func unknownTargetLeavesTheBarAlone() {
        let chrome = SongsScrollChrome()
        chrome.jump(to: keys[3], in: keys)
        #expect(!chrome.jump(to: "stale-sort-key", in: keys))
        #expect(chrome.currentSectionIndex(in: keys) == 3)
    }

    /// Measured on iPhone 17 Pro (iOS 26.5): a jump lands the title at `.scrollView`
    /// minY 116, the List's top inset. The old `minY <= 0.5` called that not passed.
    @Test func titleLandedAtTheTopInsetHasReachedTheBar() {
        #expect(SongsScrollChrome.headerPassed(minY: 116, topInset: 116))
        #expect(SongsScrollChrome.headerPassed(minY: 116.33, topInset: 116))
        #expect(SongsScrollChrome.headerPassed(minY: -400, topInset: 116))
        // The next title, one section row below, has not.
        #expect(!SongsScrollChrome.headerPassed(minY: 144, topInset: 116))
        // A bottomed-out last section ("Z" mid-screen) leaves the previous one named.
        #expect(!SongsScrollChrome.headerPassed(minY: 420, topInset: 116))
        // The expanded large title moves the bar's line down with the inset.
        #expect(SongsScrollChrome.headerPassed(minY: 228, topInset: 232))
    }

    /// Issue #298: a jump lands the title where it pins, under the bar's identical copy,
    /// so there is no gap above it and it does not slide up on the next scroll.
    @Test func landingLineIsThePinnedPlace() {
        #expect(SongsScrollChrome.landingOffset == 0)
        #expect(SongsScrollChrome.titleAlignment == 0)
        #expect(SongsScrollChrome.barTitleTopPadding == SongsScrollChrome.inlineTitleTopPadding)
        #expect(SongsScrollChrome.barTitleBottomPadding == SongsScrollChrome.inlineTitleBottomPadding)
        // A landed title (flush with the inset) has reached the bar.
        #expect(SongsScrollChrome.headerPassed(minY: 176, topInset: 176))
        #expect(SongsScrollChrome.landingCorrection(
            minY: 176, topInset: 176, landingOffset: SongsScrollChrome.landingOffset) == nil)
    }

    /// The bar names a section once its title reaches the landing line, so a landed
    /// jump names the target while its first rows are fully visible.
    @Test func titleOnTheLandingLineHasReachedTheBar() {
        #expect(SongsScrollChrome.headerPassed(minY: 206, topInset: 176, landingOffset: 30))
        #expect(SongsScrollChrome.headerPassed(minY: 206.8, topInset: 176, landingOffset: 30))
        #expect(!SongsScrollChrome.headerPassed(minY: 208, topInset: 176, landingOffset: 30))
        // The default stays flush with the inset (pre-iOS 26 opaque headers).
        #expect(!SongsScrollChrome.headerPassed(minY: 206, topInset: 176))
    }

    @Test func landingCorrectionMovesTheTitleOntoTheLine() {
        // `.top` leaves the title flush with the inset: move the content down 30.
        #expect(SongsScrollChrome.landingCorrection(
            minY: 176, topInset: 176, landingOffset: 30) == 30)
        // A List that centred the title: move it up.
        #expect(SongsScrollChrome.landingCorrection(
            minY: 450, topInset: 176, landingOffset: 30) == -244)
        // Rounding is not a landing error.
        #expect(SongsScrollChrome.landingCorrection(
            minY: 205.6, topInset: 176, landingOffset: 30) == nil)
        #expect(SongsScrollChrome.landingCorrection(
            minY: 206.4, topInset: 176, landingOffset: 30) == nil)
    }

    /// Without a located scroll view a settle gives up at once instead of retrying for
    /// every round; a title already flush ends it too.
    @Test func settleStopsWhenTheListCannotMove() async {
        let chrome = SongsScrollChrome()
        chrome.setListTopInset(176)
        let keys = ["A", "B", "C"]
        chrome.jump(to: "B", in: keys)
        chrome.watchLanding("B")
        chrome.recordTitleTop("A", minY: 900)
        // A far target placed from estimated heights: needs a move the List cannot make.
        chrome.recordTitleTop("B", minY: 450)
        // Rounds, not wall-clock time: parallel suites can hold the main actor.
        #expect(await chrome.settleLanding(on: "B", generation: chrome.jumpGeneration) == 1)
        #expect(!chrome.listNudger.moveContent(by: 30))

        chrome.jump(to: "C", in: keys)
        chrome.watchLanding("C")
        chrome.recordTitleTop("C", minY: 176.4)
        #expect(await chrome.settleLanding(on: "C", generation: chrome.jumpGeneration) == 1)
    }

    /// A newer jump ends an older settle.
    @Test func newerJumpEndsAnOlderSettle() async {
        let chrome = SongsScrollChrome()
        let keys = ["A", "B", "C"]
        chrome.jump(to: "B", in: keys)
        chrome.watchLanding("B")
        let generation = chrome.jumpGeneration
        chrome.jump(to: "C", in: keys)
        #expect(await chrome.settleLanding(on: "B", generation: generation) == 1)
    }

    // MARK: - Row fade near section starts (issue #298)

    /// A bar title height (iOS 26.5).
    private let bar: CGFloat = 32

    /// A landed title's first row meets the bar's bottom edge, so the fade there is none;
    /// it deepens 1:1 as rows scroll under the bar, up to its full height.
    @Test func fadeLeavesALandedSectionsFirstRowClear() {
        #expect(SongsScrollChrome.fadeLimit(titleTop: 0, barHeight: bar) == 0)
        #expect(SongsScrollChrome.fadeLimit(titleTop: -10, barHeight: bar) == 10)
        #expect(SongsScrollChrome.fadeLimit(titleTop: -39.7, barHeight: bar) == 39.5)
        // The shared 40 pt ramp (issue #308): fully grown 40 pt under the bar.
        #expect(SongsScrollChrome.fadeLimit(titleTop: -40, barHeight: bar) == nil)
        #expect(SongsScrollChrome.fadeLimit(titleTop: -400, barHeight: bar) == nil)
    }

    /// While the bar draws an incoming title, the fade ends at its first row; below the
    /// band it ends at the title's own top, so a visible title is never dimmed.
    @Test func fadeStopsAboveAnIncomingTitle() {
        #expect(SongsScrollChrome.fadeLimit(titleTop: 12, barHeight: bar) == 12)
        #expect(SongsScrollChrome.fadeLimit(titleTop: bar, barHeight: bar) == bar)
        #expect(SongsScrollChrome.fadeLimit(titleTop: bar + 0.5, barHeight: bar) == 0.5)
        #expect(SongsScrollChrome.fadeLimit(titleTop: bar + 20, barHeight: bar) == 20)
        #expect(SongsScrollChrome.fadeLimit(titleTop: bar + 39, barHeight: bar) == 39)
        #expect(SongsScrollChrome.fadeLimit(titleTop: bar + 40, barHeight: bar) == nil)
        #expect(SongsScrollChrome.fadeLimit(titleTop: 900, barHeight: bar) == nil)
    }

    @Test func fadeLimitIsUnknownWithoutABarOrAFiniteTop() {
        #expect(SongsScrollChrome.fadeLimit(titleTop: 10, barHeight: 0) == nil)
        #expect(SongsScrollChrome.fadeLimit(titleTop: .nan, barHeight: bar) == nil)
        #expect(SongsScrollChrome.fadeLimit(titleTop: 10, barHeight: .infinity) == nil)
    }

    /// Rows never jump as the limit switches: wherever it changes abruptly, only the
    /// blank title row lies in the fade, and the limit never fades past an in-list
    /// title's top or a landed section's first row.
    @Test func fadeNeverReachesAVisibleTitleOrALandedFirstRow() {
        for step in stride(from: -40, through: 120, by: 0.5) {
            let top = CGFloat(step)
            let limit = SongsScrollChrome.fadeLimit(titleTop: top, barHeight: bar)
                ?? PinnedHeaderEdgeFade.height
            if top > bar { #expect(limit <= top - bar) }
            if top >= 0, top <= bar { #expect(limit <= top) }
        }
    }

    @Test func rowFadeTakesTheLowestLimitAndWritesOnlyOnChange() {
        let chrome = SongsScrollChrome()
        #expect(chrome.rowFadeLimit == nil)
        #expect(chrome.setFadeLimit("S", limit: 4))
        #expect(!chrome.setFadeLimit("S", limit: 4))
        #expect(!chrome.setFadeLimit("T", limit: 20))
        #expect(chrome.rowFadeLimit == 4)
        #expect(chrome.setFadeLimit("S", limit: nil))
        #expect(chrome.rowFadeLimit == 20)
        #expect(!chrome.setFadeLimit("U", limit: .nan))
        #expect(chrome.setFadeLimit("T", limit: nil))
        #expect(chrome.rowFadeLimit == nil)
    }

    @Test func fadeLimitChangesNotifyOnlyWhenTheLowestMoves() {
        let chrome = SongsScrollChrome()
        chrome.setFadeLimit("S", limit: 4)
        let fired = JumpFlag()
        withObservationTracking { _ = chrome.rowFadeLimit } onChange: { fired.value = true }
        chrome.setFadeLimit("T", limit: 12)
        #expect(!fired.value)
        chrome.setFadeLimit("S", limit: 6)
        #expect(fired.value)
    }

    /// Runs `write` and reports whether an observer of the row mask's inputs was invalidated.
    private func rowFadeInvalidated(
        _ chrome: SongsScrollChrome, by write: (SongsScrollChrome) -> Void
    ) -> Bool {
        let fired = JumpFlag()
        withObservationTracking { _ = chrome.rowFade(enabled: true) } onChange: { fired.value = true }
        write(chrome)
        return fired.value
    }

    /// Issue #383: at the top the row mask must not follow the section bar's edge or the
    /// fade limit, which move with the expanding large title; re-rendering the List's
    /// mask there made the large title jump back and forth.
    @Test func rowFadeAtTheTopIgnoresTheMovingBar() {
        let chrome = SongsScrollChrome()
        chrome.setBarMetrics(top: 170, height: 28)
        chrome.setFadeLimit("#", limit: 12)
        #expect(chrome.rowFade(enabled: true) == .inactive)
        #expect(!rowFadeInvalidated(chrome) {
            $0.setBarMetrics(top: 172, height: 28)
        })
        #expect(!rowFadeInvalidated(chrome) {
            $0.setFadeLimit("#", limit: 0)
        })
        // Only leaving the top reaches the mask.
        #expect(rowFadeInvalidated(chrome) {
            $0.setScrolled(true)
        })
    }

    @Test func rowFadeOnceScrolledFollowsTheBarAndTheLimit() {
        let chrome = SongsScrollChrome()
        chrome.setScrolled(true)
        chrome.setBarMetrics(top: 170, height: 28)
        chrome.setFadeLimit("A", limit: 6)
        #expect(chrome.rowFade(enabled: true) == .init(edge: 198, active: true, depthLimit: 6))
        #expect(rowFadeInvalidated(chrome) {
            $0.setFadeLimit("A", limit: 2)
        })
        #expect(rowFadeInvalidated(chrome) {
            $0.setBarMetrics(top: 180, height: 28)
        })
        // No sections (or no section bar): never masked.
        #expect(chrome.rowFade(enabled: false) == .inactive)
        chrome.setScrolled(false)
        #expect(chrome.rowFade(enabled: true) == .inactive)
    }

    @Test func topInsetIgnoresNonFiniteValuesAndNotifiesNoOne() {
        let chrome = SongsScrollChrome()
        let fired = JumpFlag()
        withObservationTracking { _ = chrome.listTopInset.value } onChange: { fired.value = true }
        chrome.setListTopInset(116)
        #expect(chrome.listTopInset.value == 116)
        chrome.setListTopInset(.nan)
        #expect(chrome.listTopInset.value == 116)
        #expect(!fired.value)
    }
}

/// Set synchronously by `onChange` during a write on the main actor.
private final class JumpFlag: @unchecked Sendable {
    var value = false
}

/// Issue #9: a rail touch selects the label under the finger, not its neighbour.
@MainActor
struct SongSectionIndexHitTests {
    /// The live rail: 27 labels in a 362pt capsule with 6pt padding (iPhone 17 Pro).
    private let height: CGFloat = 362
    private let inset = SongSectionIndexScrubber.labelInset

    /// Centre of label `index` in the scrubber's own space.
    private func centre(_ index: Int, count: Int = 27) -> CGFloat {
        inset + (CGFloat(index) + 0.5) * (height - 2 * inset) / CGFloat(count)
    }

    @Test func everyLabelCentreSelectsThatLabel() {
        for index in 0..<27 {
            #expect(SongSectionIndexScrubber.sectionIndex(
                at: centre(index), height: height, inset: inset, count: 27
            ) == index)
        }
    }

    @Test func labelEdgesNearEitherEndStayOnTheirLabel() {
        let pitch = (height - 2 * inset) / 27
        // Lower part of "W" (index 23) used to select "V"; upper part of "#" chose "A".
        let w = SongSectionIndexScrubber.sectionIndex(
            at: inset + 23 * pitch + pitch * 0.1, height: height, inset: inset, count: 27
        )
        #expect(w == 23)
        let hash = SongSectionIndexScrubber.sectionIndex(
            at: inset + pitch * 0.9, height: height, inset: inset, count: 27
        )
        #expect(hash == 0)
    }

    @Test func paddingAndOutOfRangeTouchesClampToTheEnds() {
        let map = { (y: CGFloat) in
            SongSectionIndexScrubber.sectionIndex(at: y, height: self.height, inset: self.inset, count: 27)
        }
        #expect(map(0) == 0)
        #expect(map(-500) == 0)
        #expect(map(height) == 26)
        #expect(map(.greatestFiniteMagnitude) == 26)
        #expect(map(.nan) == nil)
        #expect(SongSectionIndexScrubber.sectionIndex(at: 10, height: height, inset: inset, count: 0) == nil)
        // Before the first measurement the height is 0: still a valid label.
        #expect(SongSectionIndexScrubber.sectionIndex(at: 3, height: 0, inset: inset, count: 27) == 0)
    }
}

/// The Debug in-app stress pass (issue #8 measurements).
struct SongsScrollStressTests {
    @Test func planNeedsFourSections() {
        #expect(SongsScrollStress.plan(groupCount: 3).isEmpty)
        #expect(!SongsScrollStress.plan(groupCount: 4).isEmpty)
    }

    @Test func planStaysInRangeAndReturnsToTheTop() {
        for count in [4, 12, 27] {
            let plan = SongsScrollStress.plan(groupCount: count)
            #expect(plan.count == SongsScrollStress.rounds * 10)
            #expect(plan.allSatisfy { (0..<count).contains($0.group) && $0.pause > 0 })
            #expect(plan.last?.group == 0)
            // Every jump away is followed by a jump back to the top.
            for pair in stride(from: 0, to: plan.count, by: 2) {
                #expect(plan[pair].group != 0 && plan[pair + 1].group == 0)
            }
        }
    }

    @Test func planTravelsFurtherEachRound() {
        let far = SongsScrollStress.plan(groupCount: 27).enumerated()
            .filter { $0.offset % 10 == 6 }.map(\.element.group)
        #expect(far == [10, 12, 14, 16, 18, 20])
    }
}

#if DEBUG
/// The Debug main-thread stall recorder behind `FST_DEBUG_STALL_LOG`.
struct MainThreadStallRecorderTests {
    private func recorder() -> (MainThreadStallRecorder, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stall-\(UUID().uuidString).json")
        return (MainThreadStallRecorder(url: url, startedAt: 0, clock: { 0 }), url)
    }

    @Test func measuresWorkBetweenActivitiesButNotSleep() throws {
        let (recorder, url) = recorder()
        defer { try? FileManager.default.removeItem(at: url) }
        recorder.record(.afterWaiting, at: 1.0)
        recorder.record(.beforeTimers, at: 1.02)
        recorder.record(.beforeSources, at: 1.32)
        recorder.record(.beforeWaiting, at: 1.33)
        // Ten idle seconds asleep are not a stall.
        recorder.record(.afterWaiting, at: 11.33)
        recorder.record(.beforeWaiting, at: 11.34)
        #expect(recorder.report.maxStallMs == 300)
        #expect(recorder.report.stalls == [.init(at: 1.3, ms: 300)])
        #expect(recorder.report.maxAwakeMs == 330)
        let written = try JSONDecoder().decode(
            MainThreadStallReport.self, from: Data(contentsOf: url)
        )
        #expect(written == recorder.report)
    }

    @Test func awakeSpanCatchesShortWorkThatNeverSleeps() {
        let (recorder, url) = recorder()
        defer { try? FileManager.default.removeItem(at: url) }
        recorder.record(.afterWaiting, at: 0)
        for step in 1...200 {
            recorder.record(.beforeTimers, at: Double(step) * 0.01)
        }
        recorder.record(.beforeWaiting, at: 2.01)
        #expect(recorder.report.maxStallMs < 100)
        #expect(recorder.report.stalls.isEmpty)
        #expect(recorder.report.maxAwakeMs == 2010)
    }

    @Test func marksRecordEachCountersFirstOccurrence() {
        var now = 3.0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stall-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = MainThreadStallRecorder(url: url, startedAt: 1, clock: { now })
        recorder.count("songs.stress.start")
        now = 9
        recorder.count("songs.stress.start")
        recorder.count("songs.stress.end")
        #expect(recorder.report.marks == ["songs.stress.start": 2, "songs.stress.end": 8])
        #expect(recorder.report.counters["songs.stress.start"] == 2)
        #expect(Set(recorder.report.cpuMarks?.keys ?? [:].keys) == ["songs.stress.start", "songs.stress.end"])
    }

    @Test func stallsListTheEventsCountedDuringTheirUnit() throws {
        let (recorder, url) = recorder()
        defer { try? FileManager.default.removeItem(at: url) }
        recorder.record(.afterWaiting, at: 1.0)
        recorder.count("songs.row")
        recorder.record(.beforeTimers, at: 1.01)
        recorder.count("songs.row")
        recorder.count("songs.row")
        recorder.count("songdetail.body")
        recorder.record(.beforeSources, at: 1.31)
        recorder.record(.beforeWaiting, at: 1.32)
        #expect(recorder.report.stalls.count == 1)
        #expect(recorder.report.stalls.first?.counts == ["songs.row": 2, "songdetail.body": 1])
        #expect(recorder.report.counters["songs.row"] == 3)
    }

    @Test func countersAreFlushedWhenIdle() throws {
        let (recorder, url) = recorder()
        defer { try? FileManager.default.removeItem(at: url) }
        recorder.count("songs.body")
        recorder.count("songs.body")
        recorder.record(.afterWaiting, at: 100)
        recorder.record(.beforeWaiting, at: 100.01)
        let written = try JSONDecoder().decode(
            MainThreadStallReport.self, from: Data(contentsOf: url)
        )
        #expect(written.counters == ["songs.body": 2])
    }
}
#endif
