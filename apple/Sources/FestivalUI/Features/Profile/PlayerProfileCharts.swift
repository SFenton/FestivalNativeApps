import SwiftUI
import Charts
import FestivalCore
import FestivalDesign

// Player-profile graphs (operator, 2026-09-28: "the profile page still has no
// graphs"). Ported from the web player page's per-instrument blocks
// (`FortniteFestivalWeb/src/pages/player/sections/InstrumentStatsSection.tsx`):
//
// - Rank history: the web's `RankHistoryChart` (metric `totalscore`, 30 days) —
//   Total Score bars plus a reversed global-rank line. Swift Charts has no second
//   y-axis, so the two series are two stacked charts sharing one date axis.
// - Percentiles: the web's percentile *table* (`PlayerPercentileTable.tsx`), drawn
//   as a horizontal bar chart of the same "Top N%" bands.
//
// Both are glass cards following the instrument's own stats card (never nested
// glass), each registers a depth-1 Quick Link under its instrument, exposes an
// `AXChartDescriptor`, and animates only when Reduce Motion (system or the app's
// own override) is off. Data comes only from pure reads: the compact profile
// scores and `GET /api/rankings/{instrument}/{accountId}/history`.

// MARK: - Motion

/// True when either the system or the app's own Reduce Motion override is on.
struct ChartMotion {
    let system: Bool
    let app: Bool

    /// The data-change animation to use, or nil when motion is reduced.
    var animation: Animation? { system || app ? nil : .easeOut(duration: 0.35) }
}

// MARK: - PlayerRankHistoryCard

/// One instrument's 30-day Total Score rank history for the viewed account.
///
/// Appears only once snapshots exist (like the web, which shows the chart only for
/// ranked instruments); a failed read shows an inline retry card instead.
struct PlayerRankHistoryCard: View {
    let session: FestivalSession
    let accountId: String
    let instrument: Instrument

    private enum Phase {
        case loading
        case failed(ServiceIssue)
        case loaded([PlayerRankHistorySnapshot])
    }

    private struct LoadKey: Hashable {
        let accountId: String
        let instrument: Instrument
        let retry: Int
        let publicationRevision: Int
    }

    @State private var phase = Phase.loading
    @State private var retryRevision = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    private var title: String { "\(instrument.label) Rank History" }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .loading:
                EmptyView()
            case let .failed(issue):
                FestivalGlassSection(title) {
                    ServiceStatusInline(issue, scope: "player.rank-history.\(instrument.rawValue)") {
                        retryRevision += 1
                    }
                }
                .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue).error")
            case let .loaded(points) where points.isEmpty:
                EmptyView()
            case let .loaded(points):
                FestivalGlassSection(title, subtitle: "Total Score rank over the last 30 days") {
                    RankHistoryCharts(
                        points: points, instrument: instrument,
                        motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion)
                    )
                }
                .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue)")
                .quickLinkSection(QuickLinkSection(
                    id: "rank-history:\(instrument.rawValue)", title: "Rank History",
                    icon: .system("chart.line.uptrend.xyaxis"), depth: 1, spokenTitle: title
                ))
            }
        }
        .task(id: LoadKey(
            accountId: accountId, instrument: instrument, retry: retryRevision,
            publicationRevision: session.publicationRevision
        )) {
            await load()
        }
    }

    /// Read the pure rank-history GET, never player-stats.
    private func load() async {
        phase = .loading
        do {
            let history = try await session.playerRankHistory(
                instrument: instrument, accountId: accountId
            )
            try Task.checkCancellation()
            phase = .loaded(history.rankedChronological)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(ServiceIssue(error))
        }
    }
}

/// The rank line (rank 1 at the top) above Total Score bars, plus a latest summary.
struct RankHistoryCharts: View {
    let points: [PlayerRankHistorySnapshot]
    let instrument: Instrument
    let motion: ChartMotion

    private struct Point: Identifiable, Equatable {
        let id: String
        let date: Date
        let rank: Int
        let totalScore: Int?
    }

    private var chartPoints: [Point] {
        points.compactMap { snapshot in
            snapshot.date.map {
                Point(
                    id: snapshot.snapshotDate, date: $0,
                    rank: snapshot.totalScoreRank, totalScore: snapshot.totalScore
                )
            }
        }
    }

    var body: some View {
        let data = chartPoints
        VStack(alignment: .leading, spacing: 12) {
            if let latest = points.last {
                latestSummary(latest)
            }
            // Plot -rank on an explicit padded domain: rank 1 sits on top, and the
            // axis can never round past #1 to a meaningless "#0".
            let axis = Self.rankAxis(data.map(\.rank))
            Chart(data) { point in
                LineMark(x: .value("Date", point.date, unit: .day), y: .value("Rank", -point.rank))
                    .foregroundStyle(BrandTokens.accentBlue)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date, unit: .day), y: .value("Rank", -point.rank))
                    .foregroundStyle(BrandTokens.accentBlue)
                    .symbolSize(data.count > 14 ? 14 : 30)
            }
            .chartYScale(domain: -axis.worst ... -axis.best)
            .chartYAxis {
                AxisMarks(position: .leading, values: axis.ticks.map { -$0 }) { value in
                    AxisGridLine().foregroundStyle(BrandTokens.glassBorder)
                    AxisValueLabel {
                        if let negated = value.as(Int.self) {
                            Text("#\((-negated).formatted())")
                                .foregroundStyle(FestivalText.deemphasized)
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
            .accessibilityChartDescriptor(RankLineDescriptor(points: points, instrument: instrument))
            .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue).rank-chart")

            if data.contains(where: { $0.totalScore != nil }) {
                Chart(data) { point in
                    if let totalScore = point.totalScore {
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Total Score", totalScore)
                        )
                        .foregroundStyle(BrandTokens.accentBlue.opacity(0.55))
                        .cornerRadius(2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(BrandTokens.glassBorder)
                        AxisValueLabel {
                            if let score = value.as(Int.self) {
                                Text(RankingFormatting.wholeNumber(Double(score)))
                                    .foregroundStyle(FestivalText.deemphasized)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                            .foregroundStyle(FestivalText.deemphasized)
                    }
                }
                .frame(height: 110)
                .accessibilityChartDescriptor(TotalScoreDescriptor(points: points, instrument: instrument))
                .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue).score-chart")
            }
        }
        .animation(motion.animation, value: data)
    }

    /// Padded rank bounds (best ≥ 1) and up to four whole-number ticks between them.
    ///
    /// - Parameter ranks: Charted Total Score ranks (all ≥ 1).
    /// - Returns: Best (smallest) and worst bounds plus tick ranks, best first.
    static func rankAxis(_ ranks: [Int]) -> (best: Int, worst: Int, ticks: [Int]) {
        let low = ranks.min() ?? 1
        let high = ranks.max() ?? 1
        let pad = max(1, (high - low) / 8)
        let best = max(1, low - pad)
        let worst = max(best + 1, high + pad)
        let step = max(1, Int((Double(worst - best) / 3).rounded(.up)))
        let ticks = Array(stride(from: best, through: worst, by: step))
        return (best, worst, ticks)
    }

    /// Latest rank "of N", plus Total Score when present, as one readable line.
    ///
    /// - Parameter latest: Most recent ranked snapshot.
    /// - Returns: A combined, VoiceOver-friendly summary row.
    private func latestSummary(_ latest: PlayerRankHistorySnapshot) -> some View {
        let field = latest.rankedAccountCount.map { " of \($0.formatted())" } ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            Text("#\(latest.totalScoreRank.formatted())\(field)")
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(BrandTokens.textPrimary)
            if let totalScore = latest.totalScore {
                Text("Total Score \(RankingFormatting.wholeNumber(Double(totalScore)))")
                    .font(.footnote)
                    .foregroundStyle(FestivalText.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Latest global rank \(latest.totalScoreRank.formatted())\(field)"
                + (latest.totalScore.map { ", total score \($0.formatted())" } ?? "")
        )
    }
}

// MARK: - PlayerPercentileChartCard

/// One instrument's leaderboard-placement distribution: how many songs rank in the
/// top 1%, 2%, … 100%. Hidden when no score has a known placement.
struct PlayerPercentileChartCard: View {
    let buckets: [PlayerPercentileBucket]
    let instrument: Instrument
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    private var title: String { "\(instrument.label) Percentiles" }

    var body: some View {
        if !buckets.isEmpty {
            FestivalGlassSection(title, subtitle: "Songs by leaderboard placement") {
                PercentileBandsChart(
                    buckets: buckets, instrument: instrument,
                    motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion)
                )
            }
            .accessibilityIdentifier("fst.player.percentiles.\(instrument.rawValue)")
            .quickLinkSection(QuickLinkSection(
                id: "percentiles:\(instrument.rawValue)", title: "Percentiles",
                icon: .system("chart.bar.xaxis"), depth: 1, spokenTitle: title
            ))
        }
    }

    /// "Top N%", the web's `PercentilePill` text.
    ///
    /// - Parameter bucket: One non-empty band.
    /// - Returns: Axis and VoiceOver category label.
    nonisolated static func label(_ bucket: PlayerPercentileBucket) -> String {
        "Top \(bucket.topPercent)%"
    }
}

/// The bare "Top N%" bar chart inside `PlayerPercentileChartCard` (no glass).
struct PercentileBandsChart: View {
    let buckets: [PlayerPercentileBucket]
    let instrument: Instrument
    let motion: ChartMotion

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Songs", bucket.count),
                y: .value("Placement", PlayerPercentileChartCard.label(bucket))
            )
            .foregroundStyle(bucket.topPercent <= 5 ? BrandTokens.gold : BrandTokens.accentBlue)
            .cornerRadius(3)
            .annotation(position: .trailing, alignment: .leading) {
                Text(bucket.count.formatted())
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(BrandTokens.textPrimary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(FestivalText.deemphasized)
            }
        }
        .frame(height: CGFloat(buckets.count) * 28 + 8)
        .animation(motion.animation, value: buckets)
        .accessibilityChartDescriptor(PercentileDescriptor(buckets: buckets, instrument: instrument))
    }
}

// MARK: - Audio Graph descriptors

/// VoiceOver Audio Graph for the rank line: date categories, rank values.
struct RankLineDescriptor: AXChartDescriptorRepresentable {
    let points: [PlayerRankHistorySnapshot]
    let instrument: Instrument

    func makeChartDescriptor() -> AXChartDescriptor {
        let ranks = points.map { Double($0.totalScoreRank) }
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Date", categoryOrder: points.map(\.snapshotDate)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Global rank", range: (ranks.min() ?? 0)...(ranks.max() ?? 1),
            gridlinePositions: []
        ) { "Rank \(Int($0).formatted())" }
        let series = AXDataSeriesDescriptor(
            name: "Total Score rank", isContinuous: true,
            dataPoints: points.map {
                AXDataPoint(x: $0.snapshotDate, y: Double($0.totalScoreRank))
            }
        )
        return AXChartDescriptor(
            title: "\(instrument.label) rank history",
            summary: rankSummary(points),
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }

    /// First-to-latest movement, where a lower rank number is better.
    private func rankSummary(_ points: [PlayerRankHistorySnapshot]) -> String {
        guard let first = points.first, let last = points.last else { return "No snapshots" }
        let delta = first.totalScoreRank - last.totalScoreRank
        let trend = delta > 0 ? "up \(delta.formatted()) places"
            : delta < 0 ? "down \((-delta).formatted()) places" : "unchanged"
        return "\(points.count) daily snapshots. Latest rank \(last.totalScoreRank.formatted()), \(trend)."
    }
}

/// VoiceOver Audio Graph for the Total Score bars.
struct TotalScoreDescriptor: AXChartDescriptorRepresentable {
    let points: [PlayerRankHistorySnapshot]
    let instrument: Instrument

    func makeChartDescriptor() -> AXChartDescriptor {
        let scored = points.filter { $0.totalScore != nil }
        let values = scored.compactMap { $0.totalScore.map(Double.init) }
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Date", categoryOrder: scored.map(\.snapshotDate)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Total score", range: 0...(values.max() ?? 1), gridlinePositions: []
        ) { Int($0).formatted() }
        let series = AXDataSeriesDescriptor(
            name: "Total score", isContinuous: false,
            dataPoints: scored.map {
                AXDataPoint(x: $0.snapshotDate, y: Double($0.totalScore ?? 0))
            }
        )
        return AXChartDescriptor(
            title: "\(instrument.label) total score history",
            summary: values.last.map { "Latest total score \(Int($0).formatted())." },
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}

/// VoiceOver Audio Graph for the percentile bands.
struct PercentileDescriptor: AXChartDescriptorRepresentable {
    let buckets: [PlayerPercentileBucket]
    let instrument: Instrument

    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = buckets.map(PlayerPercentileChartCard.label)
        let total = buckets.reduce(0) { $0 + $1.count }
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Placement", categoryOrder: labels)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Songs", range: 0...Double(buckets.map(\.count).max() ?? 1),
            gridlinePositions: []
        ) { "\(Int($0).formatted()) songs" }
        let series = AXDataSeriesDescriptor(
            name: "Songs", isContinuous: false,
            dataPoints: buckets.map {
                AXDataPoint(x: PlayerPercentileChartCard.label($0), y: Double($0.count))
            }
        )
        return AXChartDescriptor(
            title: "\(instrument.label) percentile distribution",
            summary: "\(total.formatted()) placed songs across \(buckets.count) bands.",
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}
