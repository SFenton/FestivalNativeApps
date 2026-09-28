import SwiftUI
import Charts
import FestivalCore
import FestivalDesign

// Player-profile graphs (operator, 2026-09-28: "the profile page still has no
// graphs"). Ported from the web player page's per-instrument blocks
// (`FortniteFestivalWeb/src/pages/player/sections/InstrumentStatsSection.tsx`):
//
// - Rank history: the web's `RankHistoryChart` (metric `totalscore`, 30 days) —
//   one combined chart of Total Score bars plus a reversed global-rank line, with the
//   rank projected onto the value scale (`RankHistoryChartScale`), a swipeable window
//   and the web's four pagination buttons (`RankHistoryPaging`).
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
                FestivalGlassSection("Rank History", subtitle: "Ranking progression over the past 30 days.") {
                    RankHistoryCharts(
                        points: points, instrument: instrument,
                        motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion)
                    )
                }
                .festivalFadeIn(isLoaded: true)
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

/// The web's combined Rank History chart: Total Score bars (leading value axis, each bar
/// coloured by its rank's place in the field) and the global-rank line (trailing, reversed
/// rank axis, bright blue with dots), one legend, a latest summary, and a swipeable window
/// of history (swipe a page at a time) with the web's four pagination buttons.
///
/// Ported from `pages/leaderboards/components/RankHistoryChart.tsx` + `GraphCard.tsx`
/// (`useChartPagination`). Swift Charts has one y scale, so ranks are projected into the
/// value range (`RankHistoryChartScale`); the trailing axis labels those positions as ranks.
struct RankHistoryCharts: View {
    let points: [PlayerRankHistorySnapshot]
    let instrument: Instrument
    let motion: ChartMotion

    /// Web `Colors.accentBlueBright` (#4C7DFF), the rank line and its dots.
    static let rankLineColor = Color(.sRGB, red: 76 / 255, green: 125 / 255, blue: 1, opacity: 1)
    /// Width reserved for the two y-axis label columns when sizing the page.
    private static let axisOverhead: CGFloat = 96

    struct Point: Identifiable, Equatable {
        let id: String
        let label: String
        let rank: Int
        let value: Double
        let rankedAccountCount: Int?
    }

    @State private var chartWidth: CGFloat = 0
    /// Snapshot date of the oldest visible bar; nil shows the newest page.
    @State private var startID: String?

    private var chartPoints: [Point] {
        points.map {
            Point(
                id: $0.snapshotDate, label: RankHistoryChartFormat.axisDate($0.snapshotDate),
                rank: $0.totalScoreRank, value: Double($0.totalScore ?? 0),
                rankedAccountCount: $0.rankedAccountCount
            )
        }
    }

    private var scale: RankHistoryChartScale {
        RankHistoryChartScale(values: chartPoints.map(\.value), ranks: chartPoints.map(\.rank))
    }

    private var paging: RankHistoryPaging {
        let plot = Double(max(0, chartWidth - Self.axisOverhead))
        let size = chartWidth > 0 ? RankHistoryPaging.pageSize(forPlotWidth: plot) : points.count
        return RankHistoryPaging(count: points.count, pageSize: size)
    }

    /// Index of the oldest visible point.
    private var start: Int {
        paging.clamp(chartPoints.firstIndex { $0.id == startID } ?? paging.latestStart)
    }

    var body: some View {
        let data = chartPoints
        let visible = Array(data[paging.visibleRange(from: start)])
        VStack(alignment: .leading, spacing: 12) {
            if let latest = points.last {
                latestSummary(latest)
            }
            HStack(spacing: 2) {
                axisTitle("Total Score", degrees: -90)
                chart(visible)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { chartWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, width in chartWidth = width }
                    })
                axisTitle("Rank", degrees: 90)
            }
            legend
            if paging.needsPagination {
                pager
            }
        }
        .animation(motion.animation, value: visible)
        .onChange(of: paging) { _, _ in startID = nil }
    }

    // MARK: Chart

    @ViewBuilder
    private func chart(_ data: [Point]) -> some View {
        let scale = scale
        let base = Chart(data) { point in
            BarMark(
                x: .value("Date", point.id),
                y: .value("Total Score", point.value),
                width: .ratio(0.9)
            )
            .foregroundStyle(Self.barColor(point).opacity(0.8))
            .cornerRadius(4)
            LineMark(
                x: .value("Date", point.id),
                y: .value("Rank", scale.y(forRank: point.rank)),
                series: .value("Series", "Rank")
            )
            .foregroundStyle(Self.rankLineColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)
            PointMark(
                x: .value("Date", point.id),
                y: .value("Rank", scale.y(forRank: point.rank))
            )
            .foregroundStyle(Self.rankLineColor)
            .symbolSize(30)
        }
        .chartYScale(domain: 0 ... scale.valueTop)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(BrandTokens.glassBorder)
                AxisValueLabel {
                    if let score = value.as(Double.self) {
                        Text(RankHistoryChartFormat.compactScore(score))
                            .foregroundStyle(FestivalText.primary)
                    }
                }
            }
            AxisMarks(position: .trailing, values: scale.rankTicks.map { scale.y(forRank: $0) }) { value in
                AxisValueLabel {
                    if let y = value.as(Double.self),
                       let rank = scale.rankTicks.first(where: { abs(scale.y(forRank: $0) - y) < 0.0001 }) {
                        Text("#\(rank.formatted())")
                            .foregroundStyle(FestivalText.primary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let id = value.as(String.self) {
                        Text(RankHistoryChartFormat.axisDate(id))
                            .foregroundStyle(FestivalText.primary)
                    }
                }
            }
        }
        .frame(height: 220)
        .accessibilityChartDescriptor(RankHistoryDescriptor(points: points, instrument: instrument))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(to: paging.forwardPage(from: start))
            case .decrement: move(to: paging.backPage(from: start))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue).chart")

        if paging.needsPagination {
            // Swipe a page at a time (web `SWIPE_THRESHOLD` 50 pt): left shows newer
            // snapshots, right older. Horizontal-dominant drags only, so the page still
            // scrolls vertically over the chart.
            base.simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { drag in
                    let dx = drag.translation.width
                    guard abs(dx) > 50, abs(dx) > abs(drag.translation.height) else { return }
                    move(to: dx < 0 ? paging.forwardPage(from: start) : paging.backPage(from: start))
                }
            )
        } else {
            base
        }
    }

    /// Bar fill: the web's `rankColor(rank, rankedAccounts)` red→green field placement.
    ///
    /// - Parameter point: One snapshot.
    /// - Returns: Opaque colour for the bar.
    static func barColor(_ point: Point) -> Color {
        let rgb = RankHistoryChartFormat.rankColor(rank: point.rank, totalAccounts: point.rankedAccountCount)
        return Color(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    /// A rotated axis title beside the plot, like the web's rotated Recharts labels.
    private func axisTitle(_ text: String, degrees: Double) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(FestivalText.primary)
            .fixedSize()
            .rotationEffect(.degrees(degrees))
            .frame(width: 16)
            .accessibilityHidden(true)
    }

    // MARK: Legend

    /// Web legend: gradient swatch "Total Score", line-and-dot "Rank".
    private var legend: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(
                        colors: [
                            Color(.sRGB, red: 220 / 255, green: 40 / 255, blue: 40 / 255),
                            Color(.sRGB, red: 46 / 255, green: 204 / 255, blue: 113 / 255),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: 16, height: 12)
                Text("Total Score")
            }
            HStack(spacing: 6) {
                ZStack(alignment: .trailing) {
                    Rectangle().fill(Self.rankLineColor).frame(width: 18, height: 2)
                    Circle().fill(Self.rankLineColor).frame(width: 6, height: 6).offset(x: 3)
                }
                .frame(width: 24, height: 12, alignment: .leading)
                Text("Rank")
            }
        }
        .font(.subheadline)
        .foregroundStyle(FestivalText.primary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: bars show Total Score, the line shows Rank")
    }

    // MARK: Pagination

    /// The web `GraphCard` pager: back a page, back an entry, forward an entry, forward a page.
    private var pager: some View {
        let paging = paging
        let start = start
        let range = paging.visibleRange(from: start)
        return HStack(spacing: 12) {
            pagerButton("chevron.left.2", label: "Back one page", id: "back-page",
                        enabled: paging.canGoBack(from: start)) { move(to: paging.backPage(from: start)) }
            pagerButton("chevron.left", label: "Back one entry", id: "back-entry",
                        enabled: paging.canGoBack(from: start)) { move(to: paging.backEntry(from: start)) }
            Text(rangeLabel(range))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(FestivalText.primary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Showing \(rangeLabel(range))")
            pagerButton("chevron.right", label: "Forward one entry", id: "forward-entry",
                        enabled: paging.canGoForward(from: start)) { move(to: paging.forwardEntry(from: start)) }
            pagerButton("chevron.right.2", label: "Forward one page", id: "forward-page",
                        enabled: paging.canGoForward(from: start)) { move(to: paging.forwardPage(from: start)) }
        }
    }

    private func rangeLabel(_ range: Range<Int>) -> String {
        let data = chartPoints
        guard let first = range.first, let last = range.last, last < data.count else { return "" }
        return first == last ? data[first].label : "\(data[first].label) – \(data[last].label)"
    }

    private func pagerButton(
        _ symbol: String, label: String, id: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(BrandTokens.glassBorder, lineWidth: 1))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? FestivalText.primary : FestivalText.disabled)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue).\(id)")
    }

    /// Show the window whose oldest visible snapshot is `index`.
    private func move(to index: Int) {
        let data = chartPoints
        guard data.indices.contains(index) else { return }
        withAnimation(motion.animation) {
            startID = index == paging.latestStart ? nil : data[index].id
        }
    }

    // MARK: Summary

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

/// VoiceOver Audio Graph for the combined chart: Total Score bars and the rank line as
/// two series over the same date categories.
struct RankHistoryDescriptor: AXChartDescriptorRepresentable {
    let points: [PlayerRankHistorySnapshot]
    let instrument: Instrument

    func makeChartDescriptor() -> AXChartDescriptor {
        let ranks = points.map { Double($0.totalScoreRank) }
        let scores = points.map { Double($0.totalScore ?? 0) }
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Date", categoryOrder: points.map(\.snapshotDate)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Total score", range: 0...(max(scores.max() ?? 1, 1)), gridlinePositions: []
        ) { Int($0).formatted() }
        let rankAxis = AXNumericDataAxisDescriptor(
            title: "Global rank", range: (ranks.min() ?? 0)...(max(ranks.max() ?? 1, (ranks.min() ?? 0) + 1)),
            gridlinePositions: []
        ) { "Rank \(Int($0).formatted())" }
        let scoreSeries = AXDataSeriesDescriptor(
            name: "Total score", isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.snapshotDate, y: Double($0.totalScore ?? 0)) }
        )
        let rankSeries = AXDataSeriesDescriptor(
            name: "Total Score rank", isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.snapshotDate, y: Double($0.totalScoreRank)) }
        )
        return AXChartDescriptor(
            title: "\(instrument.label) rank history",
            summary: rankSummary(points),
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [rankAxis], series: [scoreSeries, rankSeries]
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
