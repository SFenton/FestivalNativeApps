import Testing
@testable import FestivalCore

// MARK: - RankHistoryChartScale

@Test func rankDomainMatchesWebPaddingAndNeverPassesFirstPlace() {
    let top = RankHistoryChartScale.rankDomain([4, 6, 9, 14])
    #expect(top.best == 3 && top.worst == 15, "10% of the spread (1) pads each side")
    #expect(RankHistoryChartScale.rankDomain([1, 1, 2]).best == 1, "Rank #1 is the ceiling")
    let flat = RankHistoryChartScale.rankDomain([500])
    #expect(flat.best < flat.worst, "A single snapshot still needs a non-empty domain")
    #expect(RankHistoryChartScale.rankDomain([]) == (1, 100))
    #expect(RankHistoryChartScale.rankDomain([0, -3]) == (1, 100))
    let wide = RankHistoryChartScale.rankDomain([100, 1_100])
    #expect(wide.best == 1 && wide.worst == 1_200)
}

@Test func rankProjectionPutsBestRankAtTheValueTop() {
    let scale = RankHistoryChartScale(values: [1_000, 2_000], ranks: [10, 20])
    #expect(scale.valueTop == 2_200)
    #expect(scale.y(forRank: scale.bestRank) == scale.valueTop)
    #expect(scale.y(forRank: scale.worstRank) == 0)
    #expect(scale.y(forRank: 10) > scale.y(forRank: 20), "Better ranks plot higher")
    #expect(scale.y(forRank: 1) == scale.valueTop, "Out-of-domain ranks clamp")
    #expect(scale.rankTicks.first == scale.bestRank)
    #expect(scale.rankTicks.count <= 4 && scale.rankTicks.allSatisfy { $0 >= scale.bestRank && $0 <= scale.worstRank })
    #expect(RankHistoryChartScale(values: [], ranks: [3]).valueTop == 1)
}

// MARK: - RankHistoryChartFormat

@Test func compactScoreMatchesWebValueTicks() {
    #expect(RankHistoryChartFormat.compactScore(0) == "0")
    #expect(RankHistoryChartFormat.compactScore(950) == "950")
    #expect(RankHistoryChartFormat.compactScore(1_000) == "1K")
    #expect(RankHistoryChartFormat.compactScore(1_500) == "1.5K")
    #expect(RankHistoryChartFormat.compactScore(3_000_000) == "3M")
    #expect(RankHistoryChartFormat.compactScore(1_250_000_000) == "1.3B")
    #expect(RankHistoryChartFormat.compactScore(-2_000) == "-2K")
}

@Test func axisDateMatchesWebShortFormat() {
    #expect(RankHistoryChartFormat.axisDate("2026-09-08") == "9/8/26")
    #expect(RankHistoryChartFormat.axisDate("2026-12-28") == "12/28/26")
    #expect(RankHistoryChartFormat.axisDate("bad") == "bad")
}

@Test func rankColorMatchesWebAccuracyScale() {
    #expect(RankHistoryChartFormat.rankColor(rank: 1, totalAccounts: nil) == (127, 140, 141))
    #expect(RankHistoryChartFormat.rankColor(rank: 0, totalAccounts: 10) == (127, 140, 141))
    #expect(RankHistoryChartFormat.rankColor(rank: 10, totalAccounts: 10) == (220, 40, 40))
    let top = RankHistoryChartFormat.rankColor(rank: 1, totalAccounts: 1_000_000)
    #expect(top.red == 46 && top.green == 204 && top.blue == 113)
    #expect(RankHistoryChartFormat.rankColor(rank: 5, totalAccounts: 10) == (133, 122, 77))
}

// MARK: - RankHistoryPaging

@Test func pageSizeUsesWebMinimumBarWidthAndGap() {
    #expect(RankHistoryPaging.pageSize(forPlotWidth: 0) == 1)
    #expect(RankHistoryPaging.pageSize(forPlotWidth: 95) == 1)
    #expect(RankHistoryPaging.pageSize(forPlotWidth: 200) == 2)
    #expect(RankHistoryPaging.pageSize(forPlotWidth: 304) == 3)
}

@Test func pagingOpensOnNewestPageAndClampsEveryMove() {
    let paging = RankHistoryPaging(count: 10, pageSize: 3)
    #expect(paging.needsPagination)
    #expect(paging.latestStart == 7)
    #expect(paging.visibleRange(from: paging.latestStart) == 7..<10)
    #expect(paging.backPage(from: 7) == 4)
    #expect(paging.backEntry(from: 7) == 6)
    #expect(paging.backPage(from: 1) == 0)
    #expect(paging.forwardEntry(from: 7) == 7)
    #expect(paging.forwardPage(from: 5) == 7)
    #expect(!paging.canGoForward(from: 7) && paging.canGoBack(from: 7))
    #expect(!paging.canGoBack(from: 0) && paging.canGoForward(from: 0))
    #expect(paging.clamp(99) == 7 && paging.clamp(-4) == 0)

    let short = RankHistoryPaging(count: 2, pageSize: 5)
    #expect(!short.needsPagination && short.latestStart == 0)
    #expect(short.visibleRange(from: 0) == 0..<2)
    #expect(RankHistoryPaging(count: 0, pageSize: 0).visibleRange(from: 0).isEmpty)
}
