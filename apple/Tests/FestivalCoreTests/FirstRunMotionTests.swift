import Foundation
import Testing
@testable import FestivalCore

// MARK: - Entrance choreography

/// Every catalogued slide has the web's `contentStaggerCount`, so its text fades in on the
/// web's cadence.
@Test func everyCatalogueSlideHasAWebStaggerCount() {
    for page in FirstRunPageKey.allCases {
        for slide in FirstRunCatalog.slides(for: page) {
            #expect(FirstRunMotion.contentStaggerCounts[slide.id] != nil, "\(slide.id)")
        }
    }
}

/// The web's timing constants: 125 ms cascade steps, 80 ms row and 60 ms tile cascades,
/// 100 ms Rivals detail steps and a 200 ms exit.
@Test func motionConstantsMatchTheWeb() {
    #expect(FirstRunMotion.staggerSeconds == 0.125)
    #expect(FirstRunMotion.rowStaggerSeconds == 0.08)
    #expect(FirstRunMotion.tileStaggerSeconds == 0.06)
    #expect(FirstRunMotion.detailStaggerSeconds == 0.1)
    #expect(FirstRunMotion.exitSeconds == 0.2)
}

/// The title waits for the demo's cascade and the description one step longer.
@Test func slideTextFadesInAfterTheDemoCascade() {
    let topScores = FirstRunMotion.textDelays(slideId: "songinfo-top-scores")
    #expect(topScores.title == 0.75 && topScores.description == 0.875)
    let selectProfile = FirstRunMotion.textDelays(slideId: "statistics-select-profile")
    #expect(selectProfile.title == 0.125 && selectProfile.description == 0.25)
    let unknown = FirstRunMotion.textDelays(slideId: "not-a-slide")
    #expect(unknown.title == 0 && unknown.description == 0.125)
}

/// Reduce Motion and the UI-test still override show content at rest.
@Test func entrancesStopUnderReduceMotion() {
    #expect(FirstRunMotion.entranceAnimates(reduceMotion: false, stillBackground: false))
    #expect(!FirstRunMotion.entranceAnimates(reduceMotion: true, stillBackground: false))
    #expect(!FirstRunMotion.entranceAnimates(reduceMotion: false, stillBackground: true))
}

// MARK: - Auto-scroll

/// The glide waits 100 ms, moves 30 pt/s and jumps back to the top at the end.
@Test func autoScrollGlidesAndWraps() {
    #expect(FirstRunAutoScroll.pointsPerSecond == 30 && FirstRunAutoScroll.edgeFade == 36)
    #expect(FirstRunAutoScroll.offset(elapsed: 0.05, maxOffset: 300) == 0)
    #expect(abs(FirstRunAutoScroll.offset(elapsed: 1.1, maxOffset: 300) - 30) < 0.0001)
    #expect(abs(FirstRunAutoScroll.offset(elapsed: 10.1 + 1, maxOffset: 300) - 30) < 0.0001)
    #expect(FirstRunAutoScroll.offset(elapsed: 50, maxOffset: 0) == 0)
    #expect(FirstRunAutoScroll.offset(elapsed: 50, maxOffset: -20) == 0)
}

/// Fades sit only on edges that hide cards (web `fadeBottom`, `fadeBoth`, `fadeTop`).
@Test func autoScrollFadesTheEdgesThatHideCards() {
    typealias Edges = FirstRunAutoScroll.Edges
    #expect(FirstRunAutoScroll.edges(offset: 0, maxOffset: 300) == Edges(top: false, bottom: true))
    #expect(FirstRunAutoScroll.edges(offset: 120, maxOffset: 300) == Edges(top: true, bottom: true))
    #expect(FirstRunAutoScroll.edges(offset: 299.5, maxOffset: 300) == Edges(top: true, bottom: false))
    #expect(FirstRunAutoScroll.edges(offset: 0, maxOffset: 0) == Edges(top: false, bottom: false))
}

// MARK: - Demo models

/// Demo score rows and percentile bands can be built in code for the real page views.
@Test func demoHistoryAndPercentileModelsBuildInCode() {
    let entry = ScoreHistoryEntry(
        songId: "s", instrument: Instrument.lead.rawValue, newScore: 486_500, newRank: 1,
        accuracy: 1_000_000, isFullCombo: true, stars: 6, changedAt: "2026-09-12T12:00:00Z"
    )
    #expect(entry.newScore == 486_500 && entry.oldScore == nil && entry.scoreAchievedAt == nil)
    #expect(entry.displayDate != nil)
    let bucket = PlayerPercentileBucket(topPercent: 5, count: 12)
    #expect(bucket.id == 5 && bucket.count == 12)
}
