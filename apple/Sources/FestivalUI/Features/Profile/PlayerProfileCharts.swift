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
// - Percentiles: the web's percentile table (`PlayerPercentileTable.swift`); the Duo
//   carousel alone draws the same "Top N%" bands as a bar chart.
//
// Both are material cards following the instrument's own stats card (never nested
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
/// Shown like the web, only once ranked snapshots exist; a failed read shows an inline
/// retry card instead. While the read is in flight the card already holds the loaded
/// chart's place (``RankHistoryPlaceholder``), so the chart's arrival does not push
/// every card below it down, and it measures its own width so the chart opens on its
/// final page size instead of resizing (and animating) on its first frame.
struct PlayerRankHistoryCard: View {
    let session: FestivalSession
    let accountId: String
    let instrument: Instrument

    /// The history read's states (also the page's preload result).
    enum Phase {
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

    @State private var phase: Phase
    @State private var retryRevision = 0
    /// `LoadKey` whose read succeeded. `.task(id:)` restarts on every reappearance (Back
    /// from a pushed page), which used to reset to loading and collapse the card.
    @State private var loadedKey: LoadKey?
    /// The page already read this history: the first `.task` adopts it without a request.
    private let hasPreload: Bool

    /// Create the card.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - accountId: Viewed account.
    ///   - instrument: Played, Settings-visible chart.
    ///   - preloaded: The page's finished history read (web `PlayerPage` gates on its
    ///     data before any content appears), or nil to read here.
    init(session: FestivalSession, accountId: String, instrument: Instrument, preloaded: Phase? = nil) {
        self.session = session
        self.accountId = accountId
        self.instrument = instrument
        _phase = State(initialValue: preloaded ?? .loading)
        if case .loading? = preloaded { hasPreload = false } else { hasPreload = preloaded != nil }
    }
    /// This card's width, known from the placeholder before the chart exists.
    @State private var cardWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    private var title: String { "\(instrument.label) Rank History" }

    private var loadKey: LoadKey {
        LoadKey(
            accountId: accountId, instrument: instrument, retry: retryRevision,
            publicationRevision: session.publicationRevision
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .loading:
                FestivalGlassSection("Rank History", subtitle: "Ranking progression over the past 30 days.") {
                    RankHistoryPlaceholder(label: "Loading \(title)")
                }
                .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue).loading")
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
                    NearViewport {
                        RankHistoryPlaceholder(label: "\(title) below")
                    } content: {
                        RankHistoryCharts(
                            points: points, instrument: instrument,
                            motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion),
                            initialChartWidth: RankHistoryCharts.chartWidth(forCardWidth: cardWidth)
                        )
                    }
                }
                .festivalFadeIn(isLoaded: true)
                // `.contain` first, or the identifier replaces every tile's own.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue)")
                .quickLinkSection(QuickLinkSection(
                    id: "rank-history:\(instrument.rawValue)", title: "Rank History",
                    icon: .system("chart.line.uptrend.xyaxis"), depth: 1, spokenTitle: title
                ))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { cardWidth = $0 }
        .task(id: loadKey) {
            guard loadedKey != loadKey else { return }
            let key = loadKey
            if hasPreload, loadedKey == nil, retryRevision == 0 {
                loadedKey = key
                return
            }
            if await load(resetting: loadedKey?.accountId != key.accountId), !Task.isCancelled {
                loadedKey = key
            }
        }
    }

    /// Read the pure rank-history GET, never player-stats.
    ///
    /// - Parameter resetting: Show the placeholder first (a different account); a
    ///   reload for the same account keeps the shown chart until the new one arrives.
    /// - Returns: Whether the read succeeded.
    private func load(resetting: Bool) async -> Bool {
        if resetting { phase = .loading }
        do {
            let history = try await session.playerRankHistory(
                instrument: instrument, accountId: accountId
            )
            try Task.checkCancellation()
            phase = .loaded(history.rankedChronological)
            return true
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            phase = .failed(ServiceIssue(error))
            return false
        }
    }
}

/// Builds `content` only once its placeholder comes within about a screen of the
/// viewport, then keeps it (a one-way latch).
///
/// The player page is an eager `VStack` (Quick Links discovers its sections in tree
/// order), so every instrument's Swift Charts used to be built in the same pass as the
/// page itself, right as the push landed: on a profile with every instrument played
/// that stalled the main thread for most of a second, freezing the push and delaying
/// the fade-ins. Placeholders have the content's exact footprint, so the swap never
/// moves anything.
struct NearViewport<Placeholder: View, Content: View>: View {
    /// Global distance below the top of the screen within which content is built.
    static var reach: CGFloat { 1_700 }

    private let placeholder: Placeholder
    private let content: () -> Content
    @State private var isNear = false

    /// Create a deferred region.
    ///
    /// - Parameters:
    ///   - placeholder: Same-size stand-in drawn until the region is near the viewport.
    ///   - content: The expensive content.
    init(@ViewBuilder placeholder: () -> Placeholder, @ViewBuilder content: @escaping () -> Content) {
        self.placeholder = placeholder()
        self.content = content
    }

    /// Only the placeholder watches its position: once latched, the built content no
    /// longer re-reads its window frame on every scroll frame (issue #553).
    var body: some View {
        if isNear {
            content()
        } else {
            placeholder
                .onGeometryChange(for: Bool.self, of: { proxy in
                    Self.isNear(proxy.frame(in: .global))
                }) { near in
                    if near, !isNear { isNear = true }
                }
        }
    }

    /// Whether a region at `frame` (global) is within ``reach`` of the viewport.
    ///
    /// - Parameter frame: The placeholder's frame in window coordinates.
    /// - Returns: True when its content should be built.
    static func isNear(_ frame: CGRect) -> Bool {
        frame.minY < reach && frame.maxY > -reach
    }
}

/// The loaded Rank History chart's footprint with a spinner in the plot: the same
/// summary, plot, legend and pager heights as ``RankHistoryCharts`` (a paged series, the
/// common case), drawn invisibly.
struct RankHistoryPlaceholder: View {
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("#0 of 0").font(.title3.bold())
                Text("Total Score 0").font(.footnote)
            }
            .hidden()
            FestivalLoadingView(accessibilityLabel: label)
                .frame(maxWidth: .infinity)
                .frame(height: RankHistoryCharts.plotHeight)
            Text("Total Score").font(.subheadline).hidden()
            Color.clear.frame(height: RankHistoryCharts.pagerHeight)
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
    /// Plot height.
    static let plotHeight: CGFloat = 220
    /// Pager row height (44 pt buttons).
    static let pagerHeight: CGFloat = 44
    /// Width beside the plot inside the card: glass row insets (16 + 16) and the two
    /// rotated axis titles with their spacing (16 + 2 + 2 + 16).
    static let cardChrome: CGFloat = 68

    /// The plot's width inside a card of `cardWidth`, or 0 when not yet measured.
    ///
    /// - Parameter cardWidth: Rank History card width.
    /// - Returns: The chart's expected width.
    static func chartWidth(forCardWidth cardWidth: CGFloat) -> CGFloat {
        cardWidth > cardChrome ? cardWidth - cardChrome : 0
    }

    struct Point: Identifiable, Equatable {
        let id: String
        /// Position in the whole series: the x value, so paging only slides the window.
        let index: Int
        let label: String
        let rank: Int
        let value: Double
        let rankedAccountCount: Int?
    }

    /// Chart width: seeded from the card's measured width, then kept exact by the
    /// chart's own geometry (without animating that first correction).
    @State private var chartWidth: CGFloat
    /// Snapshot date of the oldest visible bar; nil shows the newest page.
    @State private var startID: String?

    /// Create the chart.
    ///
    /// - Parameters:
    ///   - points: Ranked snapshots, oldest first.
    ///   - instrument: Chart instrument.
    ///   - motion: Reduce Motion state.
    ///   - initialChartWidth: Expected plot width (``chartWidth(forCardWidth:)``), so the
    ///     first frame already pages correctly; 0 shows every point until measured.
    init(
        points: [PlayerRankHistorySnapshot], instrument: Instrument, motion: ChartMotion,
        initialChartWidth: CGFloat = 0
    ) {
        self.points = points
        self.instrument = instrument
        self.motion = motion
        _chartWidth = State(initialValue: initialChartWidth)
    }

    private var chartPoints: [Point] {
        points.enumerated().map { index, snapshot in
            let point = snapshot
            return Point(
                id: point.snapshotDate, index: index, label: RankHistoryChartFormat.axisDate(point.snapshotDate),
                rank: point.totalScoreRank, value: Double(point.totalScore ?? 0),
                rankedAccountCount: point.rankedAccountCount
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
        let range = paging.visibleRange(from: start)
        VStack(alignment: .leading, spacing: 12) {
            if let latest = points.last {
                latestSummary(latest)
            }
            HStack(spacing: 2) {
                axisTitle("Total Score", degrees: -90)
                chart(data, range: range)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { width in
                        guard width != chartWidth else { return }
                        // A width change re-pages without animating: the data-change
                        // animation is for paging, not for a measurement.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { chartWidth = width }
                    }
                axisTitle("Rank", degrees: 90)
            }
            legend
            if paging.needsPagination {
                pager
            }
        }
        .onChange(of: paging) { _, _ in startID = nil }
    }

    // MARK: Chart

    /// Every point is plotted at its series index and the x domain is the visible
    /// window, so paging slides the window (animated) while points keep their places
    /// instead of re-laying out (operator batch 7.11).
    @ViewBuilder
    private func chart(_ data: [Point], range: Range<Int>) -> some View {
        let scale = scale
        let barWidth = max(8, (chartWidth - Self.axisOverhead) / CGFloat(max(1, range.count)) * 0.85)
        let visible = data.filter { range.contains($0.index) }
        let base = Chart(data) { point in
            BarMark(
                x: .value("Date", point.index),
                y: .value("Total Score", point.value),
                width: .fixed(barWidth)
            )
            .foregroundStyle(Self.barColor(point).opacity(0.8))
            .cornerRadius(4)
            LineMark(
                x: .value("Date", point.index),
                y: .value("Rank", scale.y(forRank: point.rank)),
                series: .value("Series", "Rank")
            )
            .foregroundStyle(Self.rankLineColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)
            .accessibilityHidden(true)
            PointMark(
                x: .value("Date", point.index),
                y: .value("Rank", scale.y(forRank: point.rank))
            )
            .foregroundStyle(Self.rankLineColor)
            .symbolSize(30)
            .accessibilityHidden(true)
        }
        .chartYScale(domain: 0 ... scale.valueTop)
        .chartXScale(domain: Double(range.lowerBound) - 0.5 ... Double(max(range.lowerBound + 1, range.upperBound)) - 0.5)
        .chartPlotStyle { $0.clipped() }
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
        .barChartDateAxis(values: visible.map(\.index)) { data.indices.contains($0) ? data[$0].label : nil }
        .chartPlotFrameReporter()
        .frame(height: Self.plotHeight)
        // One adjustable element over the whole plot (HIG Charts: "When marks are too
        // small to target, consider making the whole plot area the hit target"). Per-bar
        // elements were audited "Hit area is too small" at 18.8 pt on the iPhone Duo inner
        // display in portrait, adjustable action or not (Lane A11Y3/A11Y4). The value
        // reads every visible snapshot; swiping up/down pages, as the pager buttons do.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(instrument.label) rank history chart")
        .accessibilityValue(Self.accessibilityValue(page: visible))
        .accessibilityChartDescriptor(RankHistoryDescriptor(points: points, instrument: instrument))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(to: paging.forwardPage(from: start))
            case .decrement: move(to: paging.backPage(from: start))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("fst.player.rank-history.\(instrument.rawValue).chart")
        .chartAxisElements(ChartAxisLabels(
            leading: "Total Score scale, 0 to \(RankHistoryChartFormat.compactScore(scale.valueTop))",
            trailing: "Rank scale, " + ChartAxisLabels.span(
                scale.rankTicks.first.map { "#\($0.formatted())" }, scale.rankTicks.last.map { "#\($0.formatted())" }
            ),
            bottom: "Dates, " + ChartAxisLabels.span(visible.first?.label, visible.last?.label)
        ))

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
    ///
    /// Read as "Total Score axis" before the bars and "Rank axis" after them: visible
    /// text hidden from assistive technologies was what the iPad audit reported as
    /// "Potentially inaccessible text" on Statistics.
    private func axisTitle(_ text: String, degrees: Double) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(FestivalText.primary)
            .fixedSize()
            .rotationEffect(.degrees(degrees))
            .frame(width: 16)
            .accessibilityLabel("\(text) axis")
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
        // Static text, not a control: inside the swipe-to-page chart the audit
        // otherwise judged it an 18 pt-tall interactive element ("Hit area is too small").
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Pagination

    /// The web `GraphCard` pager: back a page, back an entry, forward an entry, forward a page.
    private var pager: some View {
        let paging = paging
        let start = start
        let range = paging.visibleRange(from: start)
        return HStack(spacing: 12) {
            pagerButton("chevron.backward.2", label: "Back one page", id: "back-page",
                        enabled: paging.canGoBack(from: start)) { move(to: paging.backPage(from: start)) }
            pagerButton("chevron.backward", label: "Back one entry", id: "back-entry",
                        enabled: paging.canGoBack(from: start)) { move(to: paging.backEntry(from: start)) }
            Text(rangeLabel(range))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(FestivalText.primary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Showing \(rangeLabel(range))")
            pagerButton("chevron.forward", label: "Forward one entry", id: "forward-entry",
                        enabled: paging.canGoForward(from: start)) { move(to: paging.forwardEntry(from: start)) }
            pagerButton("chevron.forward.2", label: "Forward one page", id: "forward-page",
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

    /// One snapshot's rank (of N) and Total Score, as the chart element reads it.
    ///
    /// - Parameter point: One plotted snapshot.
    /// - Returns: For example "Rank 4 of 506, total score 89,400,000".
    static func accessibilityValue(_ point: Point) -> String {
        let field = point.rankedAccountCount.map { " of \($0.formatted())" } ?? ""
        return "Rank \(point.rank.formatted())\(field), total score \(Int(point.value).formatted())"
    }

    /// The chart element's value: each visible snapshot's date, rank and Total Score,
    /// oldest first.
    ///
    /// - Parameter page: The snapshots in the plot now.
    /// - Returns: "9/26/26: Rank 12, total score 1,000; 9/27/26: Rank 4 of 506, …".
    static func accessibilityValue(page: [Point]) -> String {
        page.map { "\($0.label): \(accessibilityValue($0))" }.joined(separator: "; ")
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
        // Wrap instead of truncating: at AX5 in a two-column iPad page the card proposed
        // one line and "Total Score 89,400,000" read "Total Score 89,4…" (Lane A11Y3).
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Latest global rank \(latest.totalScoreRank.formatted())\(field)"
                + (latest.totalScore.map { ", total score \($0.formatted())" } ?? "")
        )
    }
}

// MARK: - PercentileBandsChart

/// The "Top N%" bar chart used by the iPhone Duo graphs carousel (`PlayerPercentilePage`);
/// the stacked page shows the web's percentile table instead (`PlayerPercentileTableCard`).
struct PercentileBandsChart: View {
    let buckets: [PlayerPercentileBucket]
    let instrument: Instrument
    let motion: ChartMotion

    /// Plot height: 28 pt per band plus insets.
    ///
    /// - Parameter bucketCount: Non-empty bands.
    /// - Returns: The chart's fixed height.
    static func height(bucketCount: Int) -> CGFloat { CGFloat(bucketCount) * 28 + 8 }

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Songs", bucket.count),
                y: .value("Placement", PlayerPercentileTableCard.label(bucket))
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
        .frame(height: Self.height(bucketCount: buckets.count))
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
        let labels = buckets.map(PlayerPercentileTableCard.label)
        let total = buckets.reduce(0) { $0 + $1.count }
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Placement", categoryOrder: labels)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Songs", range: 0...Double(buckets.map(\.count).max() ?? 1),
            gridlinePositions: []
        ) { "\(Int($0).formatted()) songs" }
        let series = AXDataSeriesDescriptor(
            name: "Songs", isContinuous: false,
            dataPoints: buckets.map {
                AXDataPoint(x: PlayerPercentileTableCard.label($0), y: Double($0.count))
            }
        )
        return AXChartDescriptor(
            title: "\(instrument.label) percentile distribution",
            summary: "\(total.formatted()) placed songs across \(buckets.count) bands.",
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}
