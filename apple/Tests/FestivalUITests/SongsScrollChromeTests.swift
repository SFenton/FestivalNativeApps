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

    /// Normal landing line (2 + 28 pt fade) and bar title height.
    private let landing: CGFloat = 30
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
        #expect(SongsScrollChrome.pushBandTop(titleTop: 20, landingOffset: landing, barHeight: -5) == 20)
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

    /// Issue #286: a jump lands the title under the bar's label and the first row below
    /// the 28 pt soft edge (iOS 26.5: bar label 30 pt tall, in-list title 8 + 2 pt pads).
    @Test func landingLineClearsTheBarAndItsFade() {
        #expect(SongsScrollChrome.landingOffset(fade: 28) == 30)
        // Reduce Transparency / Less Transparency / Increase Contrast: a hard edge.
        #expect(SongsScrollChrome.landingOffset(fade: 0) == 2)
        #expect(SongsScrollChrome.landingOffset(fade: -10) == 2)
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

    @Test func landingLineIgnoresNonFiniteAndNegativeOffsets() {
        let chrome = SongsScrollChrome()
        chrome.setLandingLine(30)
        #expect(chrome.landingLine.value == 30)
        chrome.setLandingLine(.nan)
        #expect(chrome.landingLine.value == 30)
        chrome.setLandingLine(-4)
        #expect(chrome.landingLine.value == 0)
    }

    /// Without a located scroll view (or with no landing line) a settle gives up at
    /// once instead of retrying for every round.
    @Test func settleStopsWhenTheListCannotMove() async {
        let chrome = SongsScrollChrome()
        chrome.setLandingLine(30)
        chrome.setListTopInset(176)
        let keys = ["A", "B", "C"]
        chrome.jump(to: "B", in: keys)
        chrome.watchLanding("B")
        chrome.recordTitleTop("A", minY: 900)
        chrome.recordTitleTop("B", minY: 176)
        // Rounds, not wall-clock time: parallel suites can hold the main actor.
        #expect(await chrome.settleLanding(on: "B", generation: chrome.jumpGeneration) == 1)
        #expect(!chrome.listNudger.moveContent(by: 30))

        chrome.setLandingLine(0)
        chrome.watchLanding("C")
        #expect(await chrome.settleLanding(on: "C", generation: chrome.jumpGeneration) == 0)
    }

    /// A newer jump ends an older settle.
    @Test func newerJumpEndsAnOlderSettle() async {
        let chrome = SongsScrollChrome()
        chrome.setLandingLine(30)
        let keys = ["A", "B", "C"]
        chrome.jump(to: "B", in: keys)
        chrome.watchLanding("B")
        let generation = chrome.jumpGeneration
        chrome.jump(to: "C", in: keys)
        #expect(await chrome.settleLanding(on: "B", generation: generation) == 1)
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
