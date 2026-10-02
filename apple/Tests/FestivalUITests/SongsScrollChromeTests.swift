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

    @Test func toolsInBarWritesOnlyOnChange() {
        let chrome = SongsScrollChrome()
        #expect(!invalidates(chrome, reading: { _ = $0.toolsInBar }) { $0.setToolsInBar(false) })
        #expect(invalidates(chrome, reading: { _ = $0.toolsInBar }) { $0.setToolsInBar(true) })
        #expect(!chrome.setToolsInBar(true))
        #expect(chrome.setToolsInBar(false))
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
        #expect(!invalidates(chrome, reading: { _ = $0.toolsInBar }) {
            $0.setScrolled(true)
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
