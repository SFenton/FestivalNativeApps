#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Player profile graphs

// Hosted coverage for `PlayerProfileCharts.swift`: the rank-history card reads
// only the pure history GET and paints a chart once snapshots arrive, and hides
// for an unranked account; the percentile card paints its bands (gold for the
// top 5%) and hides when nothing is placed; the rank axis never rounds past #1.

/// Serves `/api/publication` and one rank-history body; rejects every other route.
private actor RankHistoryTransport: HTTPTransport {
    let historyJSON: String
    private var paths: [String] = []

    /// - Parameter historyJSON: Body for any `/history` request.
    init(historyJSON: String) { self.historyJSON = historyJSON }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        paths.append(path)
        guard request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil else {
            throw FestivalAPIError.invalidResource
        }
        if path == "/api/publication" {
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        guard path.hasSuffix("/history") else { throw FestivalAPIError.invalidResource }
        return HTTPResult(
            status: 200, data: Data(historyJSON.utf8), headers: ["X-FST-Publication-Id": "7"]
        )
    }

    /// Every route requested, in order.
    func recordedPaths() -> [String] { paths }
}

/// A three-day ranked series for `fixture-player-1` on Lead.
private let threeDayHistory = """
{"instrument":"Solo_Guitar","accountId":"fixture-player-1","history":[
 {"snapshotDate":"2026-09-25","adjustedSkillRank":9,"weightedRank":9,"fcRateRank":9,
  "totalScoreRank":9,"maxScorePercentRank":9,"totalScore":88000000,"rankedAccountCount":500},
 {"snapshotDate":"2026-09-26","adjustedSkillRank":7,"weightedRank":7,"fcRateRank":7,
  "totalScoreRank":7,"maxScorePercentRank":7,"totalScore":88500000,"rankedAccountCount":501},
 {"snapshotDate":"2026-09-27","adjustedSkillRank":4,"weightedRank":4,"fcRateRank":4,
  "totalScoreRank":4,"maxScorePercentRank":4,"totalScore":89500000,"rankedAccountCount":502}]}
"""

/// Host `content` at phone width until `settle` holds, then report its fitted height.
///
/// Glass cards do not paint through `cacheDisplay` offscreen (the existing Compete
/// render captures are blank too), so card visibility is asserted from layout, and
/// chart pixels from `ImageRenderer` on the bare (non-glass) chart views below.
///
/// - Parameters:
///   - content: View under test.
///   - settle: Condition that ends the wait early.
/// - Returns: The host's fitting height once settled.
@MainActor
private func fittedHeight<Content: View>(
    _ content: Content, until settle: () async -> Bool = { true }
) async throws -> CGFloat {
    let host = NSHostingView(rootView: content.frame(width: 390).preferredColorScheme(.dark))
    host.frame = CGRect(x: 0, y: 0, width: 390, height: 900)
    for _ in 0..<40 {
        host.layoutSubtreeIfNeeded()
        if await settle() { break }
        try await Task.sleep(for: .milliseconds(25))
    }
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    return host.fittingSize.height
}

/// Render a bare chart with `ImageRenderer` over the app background.
///
/// - Parameter chart: A non-glass chart view.
/// - Returns: Rendered pixels at 2× scale.
@MainActor
private func chartPixels<Content: View>(_ chart: Content) throws -> CGImage {
    let renderer = ImageRenderer(content: chart
        .frame(width: 358)
        .padding(16)
        .background(BrandTokens.appBackground)
        .environment(\.colorScheme, .dark))
    renderer.scale = 2
    return try #require(renderer.cgImage)
}

@MainActor
@Test func rankHistoryCardReadsOnlyThePureHistoryRouteAndAppearsWithData() async throws {
    let transport = RankHistoryTransport(historyJSON: threeDayHistory)
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let height = try await fittedHeight(
        PlayerRankHistoryCard(session: session, accountId: "fixture-player-1", instrument: .lead),
        until: { await transport.recordedPaths().contains { $0.hasSuffix("/history") } }
    )
    let paths = await transport.recordedPaths()
    #expect(paths.contains("/api/rankings/Solo_Guitar/fixture-player-1/history"))
    #expect(!paths.contains { $0.contains("/stats") })
    #expect(height > 250, "The rank-history card did not appear once snapshots loaded")
}

@MainActor
@Test func rankHistoryCardStaysHiddenForAnUnrankedAccount() async throws {
    let transport = RankHistoryTransport(historyJSON: """
    {"instrument":"Solo_Guitar","accountId":"fixture-player-1","history":[]}
    """)
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let height = try await fittedHeight(
        PlayerRankHistoryCard(session: session, accountId: "fixture-player-1", instrument: .lead),
        until: { await transport.recordedPaths().contains { $0.hasSuffix("/history") } }
    )
    #expect(height < 1, "An unranked account must show no card")
}

@MainActor
@Test func rankHistoryChartsPaintTheRankLineAndScoreBars() throws {
    let history = try JSONDecoder().decode(PlayerRankHistory.self, from: Data(threeDayHistory.utf8))
    let image = try chartPixels(RankHistoryCharts(
        points: history.rankedChronological, instrument: .lead,
        motion: ChartMotion(system: true, app: false)
    ))
    let pixels = nativeHostedControlPixels(image)
    #expect(pixels.selected > 40, "The accent-blue rank line and score bars did not paint")
    #expect(pixels.bright > 20, "The latest-rank summary did not paint")
    _ = try nativeHostedPNG(image, filename: "profile-rank-history.png", environment: "FST_PROFILE_RENDER_OUT")
}

@MainActor
@Test func percentileChartPaintsGoldTopBandsAndTheCardHidesWhenEmpty() async throws {
    let buckets = [
        PlayerPercentileBucket(topPercent: 1, count: 3),
        PlayerPercentileBucket(topPercent: 10, count: 5),
        PlayerPercentileBucket(topPercent: 50, count: 2),
    ]
    let image = try chartPixels(PercentileBandsChart(
        buckets: buckets, instrument: .lead, motion: ChartMotion(system: false, app: true)
    ))
    #expect(nativeHostedStatusPixels(image).gold > 10, "Top 1% band should be gold")
    #expect(nativeHostedControlPixels(image).selected > 20, "Wider bands should be accent blue")
    _ = try nativeHostedPNG(image, filename: "profile-percentiles.png", environment: "FST_PROFILE_RENDER_OUT")

}

@MainActor
@Test func percentileTableShowsOneRowPerBandAndHidesWhenEmpty() async throws {
    let buckets = [
        PlayerPercentileBucket(topPercent: 1, count: 3),
        PlayerPercentileBucket(topPercent: 10, count: 5),
        PlayerPercentileBucket(topPercent: 50, count: 2),
    ]
    let linked = PlayerPercentileTableCard(
        buckets: buckets, instrument: .lead, linkFilter: { $0 }, onSelect: { _ in }
    )
    // Header plus three 44 pt rows.
    #expect(try await fittedHeight(linked) > 150)
    #expect(try await fittedHeight(PlayerPercentileTableCard(
        buckets: [], instrument: .lead, linkFilter: { $0 }, onSelect: { _ in }
    )) < 1)
    #expect(PlayerPercentileTableCard.label(buckets[0]) == "Top 1%")
    // Every row links to Songs filtered to its band (web `instPercentileBucketUpdater`).
    #expect(PlayerStatLinks.percentileBucket(.lead, percentile: 10)
        == .songs(.percentileBucket(.lead, percentile: 10)))
}

// MARK: - Accessibility and motion

@Test func chartDescriptorsNarrateEverySnapshotAndBand() throws {
    let history = try JSONDecoder().decode(PlayerRankHistory.self, from: Data(threeDayHistory.utf8))
    let combined = RankHistoryDescriptor(points: history.rankedChronological, instrument: .lead)
        .makeChartDescriptor()
    #expect(combined.title == "Lead rank history")
    #expect(combined.series.map(\.name) == ["Total score", "Total Score rank"])
    #expect(combined.series.allSatisfy { $0.dataPoints.count == 3 })
    #expect(combined.additionalAxes.count == 1, "The rank line keeps its own axis")
    #expect(combined.summary?.contains("Latest rank 4, up 5 places") == true)
    let bands = PercentileDescriptor(
        buckets: [PlayerPercentileBucket(topPercent: 1, count: 3)], instrument: .bass
    ).makeChartDescriptor()
    #expect(bands.summary == "3 placed songs across 1 bands.")
    let placement = try #require(bands.xAxis as? AXCategoricalDataAxisDescriptor)
    #expect(placement.categoryOrder == ["Top 1%"])
}

@Test func chartMotionHonoursSystemAndAppReduceMotion() {
    #expect(ChartMotion(system: false, app: false).animation != nil)
    #expect(ChartMotion(system: true, app: false).animation == nil)
    #expect(ChartMotion(system: false, app: true).animation == nil)
}

// MARK: - Quick Links spoken titles

@Test func graphQuickLinksShowShortTitlesButSpeakTheInstrument() {
    let nested = QuickLinkSection(
        id: "rank-history:Solo_Guitar", title: "Rank History",
        icon: .system("chart.line.uptrend.xyaxis"), depth: 1, spokenTitle: "Lead Rank History"
    )
    #expect(nested.title == "Rank History")
    #expect(nested.accessibilityTitle == "Lead Rank History")
    #expect(QuickLinkSection(id: "global", title: "Global Statistics").accessibilityTitle
        == "Global Statistics")
}

/// Each rank-history bar speaks its snapshot's rank and Total Score (VoiceOver otherwise
/// reads Swift Charts' plotted index range, "0 to 1").
@MainActor
@Test func rankHistoryBarsSpeakRankAndTotalScore() {
    let point = RankHistoryCharts.Point(
        id: "2026-09-27", index: 6, label: "9/27/26", rank: 4, value: 89_400_000, rankedAccountCount: 506
    )
    #expect(RankHistoryCharts.accessibilityValue(point) == "Rank 4 of 506, total score 89,400,000")
    let unranked = RankHistoryCharts.Point(
        id: "2026-09-26", index: 5, label: "9/26/26", rank: 12, value: 1_000, rankedAccountCount: nil
    )
    #expect(RankHistoryCharts.accessibilityValue(unranked) == "Rank 12, total score 1,000")
}
#endif
