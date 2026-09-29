import Foundation
import Testing
@testable import FestivalCore

// MARK: - SettingsReorder

@Suite("SettingsReorder")
struct SettingsReorderTests {
    @Test("A drag moves one slot per full row, rounding at half a row")
    func destinationRounds() {
        #expect(SettingsReorder.destination(from: 2, translation: 0, rowHeight: 44, count: 5) == 2)
        #expect(SettingsReorder.destination(from: 2, translation: 21, rowHeight: 44, count: 5) == 2)
        #expect(SettingsReorder.destination(from: 2, translation: 23, rowHeight: 44, count: 5) == 3)
        #expect(SettingsReorder.destination(from: 2, translation: -90, rowHeight: 44, count: 5) == 0)
        #expect(SettingsReorder.destination(from: 0, translation: 132, rowHeight: 44, count: 5) == 3)
    }

    @Test("Destinations clamp to the list and reject invalid input")
    func destinationClamps() {
        #expect(SettingsReorder.destination(from: 1, translation: 999, rowHeight: 44, count: 5) == 4)
        #expect(SettingsReorder.destination(from: 3, translation: -999, rowHeight: 44, count: 5) == 0)
        #expect(SettingsReorder.destination(from: 1, translation: 50, rowHeight: 0, count: 5) == 1)
        #expect(SettingsReorder.destination(from: 1, translation: .nan, rowHeight: 44, count: 5) == 1)
        #expect(SettingsReorder.destination(from: 7, translation: 50, rowHeight: 44, count: 5) == 7)
        #expect(SettingsReorder.destination(from: 0, translation: 50, rowHeight: 44, count: 0) == 0)
    }

    @Test("moved matches dnd-kit arrayMove in both directions")
    func movedLikeArrayMove() {
        let items = ["a", "b", "c", "d"]
        #expect(SettingsReorder.moved(items, from: 0, to: 2) == ["b", "c", "a", "d"])
        #expect(SettingsReorder.moved(items, from: 3, to: 1) == ["a", "d", "b", "c"])
        #expect(SettingsReorder.moved(items, from: 1, to: 1) == items)
        #expect(SettingsReorder.moved(items, from: 9, to: 1) == items)
        #expect(SettingsReorder.moved(items, from: 1, to: -1) == items)
    }

    @Test("Hidden fields keep their relative order after the visible ones")
    func mergingKeepsHiddenFields() {
        let full = ["score", "percentage", "percentile", "stars", "season"]
        let visibleReordered = ["stars", "score", "season"]
        #expect(
            SettingsReorder.merging(visible: visibleReordered, into: full)
                == ["stars", "score", "season", "percentage", "percentile"]
        )
        #expect(SettingsReorder.merging(visible: [], into: full) == full)
    }

    @Test("Position description is one-based")
    func positionDescription() {
        #expect(SettingsReorder.positionDescription("Score", index: 0, count: 8) == "Score, 1 of 8")
    }

    @Test("Moving path columns round-trips through the order codec")
    func pathColumnsRoundTrip() {
        let moved = SettingsReorder.moved(PathColumnKey.allCases, from: 4, to: 0)
        #expect(moved == [.score, .note, .beat, .time, .od])
        #expect(SettingsOrder.decode(SettingsOrder.encode(moved)) == moved)
    }
}

// MARK: - InvalidScoreFilter

@Suite("InvalidScoreFilter")
struct InvalidScoreFilterTests {
    @Test("Leeway snaps to 0.1 % inside ±5 %")
    func normalizes() {
        #expect(InvalidScoreFilter.normalized(1.04) == 1.0)
        #expect(InvalidScoreFilter.normalized(1.05) == 1.1)
        #expect(InvalidScoreFilter.normalized(-2.26) == -2.3)
        #expect(InvalidScoreFilter.normalized(7) == 5)
        #expect(InvalidScoreFilter.normalized(-9) == -5)
        #expect(InvalidScoreFilter.normalized(.infinity) == InvalidScoreFilter.defaultLeeway)
        #expect(InvalidScoreFilter.normalized(.nan) == InvalidScoreFilter.defaultLeeway)
    }

    @Test("Leeway is only queried while the filter is on")
    func queryLeeway() {
        #expect(InvalidScoreFilter.queryLeeway(enabled: false, leeway: 1) == nil)
        #expect(InvalidScoreFilter.queryLeeway(enabled: true, leeway: 1) == 1)
        #expect(InvalidScoreFilter.queryLeeway(enabled: true, leeway: 2.345) == 2.3)
    }

    @Test("The query value builds the service's leeway parameter")
    func queryReachesRequest() throws {
        let leeway = InvalidScoreFilter.queryLeeway(enabled: true, leeway: 1)
        let url = try PublicEndpoint.leaderboard(
            songId: "song", instrument: "Solo_Guitar", top: 25, offset: 0, leeway: leeway
        ).url(relativeTo: URL(string: "https://example.test")!)
        #expect(url.query == "top=25&offset=0&leeway=1.0")
    }

    @Test("Ceiling follows maxScore × (1 + leeway / 100), like the web example")
    func ceiling() {
        #expect(InvalidScoreFilter.ceiling(maxScore: 100_000, leeway: 1) == 101_000)
        #expect(InvalidScoreFilter.ceiling(maxScore: 100_000, leeway: -5) == 95_000)
        #expect(InvalidScoreFilter.ceiling(maxScore: 81_996, leeway: 1) == 82_816)
    }

    @Test("Scores above the ceiling are invalid; an unknown maximum proves nothing")
    func validity() {
        #expect(InvalidScoreFilter.isValid(score: 82_816, maxScore: 81_996, leeway: 1))
        #expect(!InvalidScoreFilter.isValid(score: 82_817, maxScore: 81_996, leeway: 1))
        #expect(InvalidScoreFilter.isValid(score: 999_999, maxScore: nil, leeway: 1))
        #expect(InvalidScoreFilter.isValid(score: 999_999, maxScore: 0, leeway: 1))
    }

    /// Winterfest Wish Lead's live top ten (production, 2026-09-28) against its CHOpt max
    /// 81,996: every one of them is above the +1 % ceiling, which is why the service's
    /// filtered board starts at 79,243.
    @Test("Winterfest Wish Lead's live top ten is entirely invalid at +1 %")
    func winterfestWishLead() {
        let liveTopTen = [100_955, 100_823, 99_605, 99_559, 98_693, 98_452, 98_368, 97_928, 97_859, 97_832]
        #expect(InvalidScoreFilter.invalidCount(liveTopTen, maxScore: 81_996, leeway: 1) == 10)
        #expect(InvalidScoreFilter.isValid(score: 79_243, maxScore: 81_996, leeway: 1))
        #expect(InvalidScoreFilter.invalidCount(liveTopTen, maxScore: 81_996, leeway: 5) == 10)
    }
}

// MARK: - FirstRunViewing

@Suite("FirstRunViewing")
struct FirstRunViewingTests {
    private let slides = (1...4).map {
        FirstRunSlide(id: "s\($0)", version: 1, title: "T\($0)", description: "D\($0)")
    }

    @Test("The first page counts as seen as soon as the guide opens")
    func firstPageSeen() {
        let viewing = FirstRunViewing(slides: slides)
        #expect(viewing.seenSlides(slides).map(\.id) == ["s1"])
        #expect(FirstRunViewing(slides: []).seenSlides([]).isEmpty)
    }

    @Test("Only pages actually shown are marked seen, in presentation order")
    func onlyViewedPages() {
        var viewing = FirstRunViewing(slides: slides)
        viewing.view(2, of: slides)
        viewing.view(9, of: slides)
        #expect(viewing.seenSlides(slides).map(\.id) == ["s1", "s3"])
    }

    @Test("Unviewed pages stay unseen for the next presentation")
    func unviewedPagesReturn() {
        let defaults = UserDefaults(suiteName: "fst.firstRun.viewing.\(UUID())")!
        let store = FirstRunSeenStore(defaults: defaults)
        var viewing = FirstRunViewing(slides: slides)
        viewing.view(1, of: slides)
        store.markSeen(viewing.seenSlides(slides))
        let next = FirstRunSlideEvaluator.unseenSlides(
            slides, context: FirstRunGateContext(), seen: store.load()
        )
        #expect(next.map(\.id) == ["s3", "s4"])
    }

    @Test("A one-page guide shows only Done; Back after the first page; Skip until the last")
    func controls() {
        #expect(FirstRunControls.forPage(0, of: 1) == FirstRunControls(
            primaryTitle: "Done", primaryFinishes: true, showsBack: false, showsSkip: false))
        #expect(FirstRunControls.forPage(0, of: 3) == FirstRunControls(
            primaryTitle: "Next", primaryFinishes: false, showsBack: false, showsSkip: true))
        #expect(FirstRunControls.forPage(1, of: 3) == FirstRunControls(
            primaryTitle: "Next", primaryFinishes: false, showsBack: true, showsSkip: true))
        #expect(FirstRunControls.forPage(2, of: 3) == FirstRunControls(
            primaryTitle: "Done", primaryFinishes: true, showsBack: true, showsSkip: false))
    }
}
