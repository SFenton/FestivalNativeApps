import Foundation
import Testing
@testable import FestivalCore

@Test func competeIsReadyOnlyOnceEveryBoardAndRivalsReadSettles() {
    var progress = CompeteLoadProgress(boards: [.pending, .pending], rivals: [.pending, .pending])
    #expect(!progress.isReady)

    // Boards answered but a rivals list still loading: no headers yet (web `rivalsReady`).
    progress.boards = [.loaded, .failed]
    progress.rivals = [.loaded, .pending]
    #expect(!progress.isSettled)
    #expect(!progress.isReady)

    progress.rivals = [.loaded, .failed]
    #expect(progress.isSettled)
    #expect(progress.isReady)
    // A failed card retries on return rather than keeping its error.
    #expect(!progress.isComplete)

    progress.boards = [.loaded, .loaded]
    progress.rivals = [.loaded, .loaded]
    #expect(progress.isComplete)
}

@Test func competeIsReadyWhenEveryBoardFailsWhileRivalsStillLoad() {
    // Web `allLeaderboardsErrored`: the page-wide error shows without waiting for rivals.
    let progress = CompeteLoadProgress(boards: [.failed, .failed], rivals: [.pending, .loaded])
    #expect(progress.everyBoardFailed)
    #expect(!progress.isSettled)
    #expect(progress.isReady)
    #expect(!progress.isComplete)

    let oneBoardLeft = CompeteLoadProgress(boards: [.failed, .pending], rivals: [.loaded, .loaded])
    #expect(!oneBoardLeft.everyBoardFailed)
    #expect(!oneBoardLeft.isReady)
}

@Test func competeWithNoInstrumentsIsReadyWithoutAPageError() {
    // No visible instruments: the "enable an instrument" copy, never the page-wide error.
    let progress = CompeteLoadProgress(boards: [], rivals: [])
    #expect(!progress.everyBoardFailed)
    #expect(progress.isReady)
    #expect(progress.isComplete)
}
