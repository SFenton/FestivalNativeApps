import SwiftUI
import Charts
import FestivalCore
import FestivalDesign

// MARK: - SongScoreHistorySection

/// The selected player's score history **on the song page** (operator batch 6.39), the
/// native port of the web `ScoreHistoryChart` in its `GraphCard`
/// (`pages/songinfo/components/chart/ScoreHistoryChart.tsx`):
///
/// - a required `InstrumentSelector` (graph look) over the instruments with history,
///   shown even for one instrument (web `showSingleInstrumentSelector`);
/// - a combined chart: accuracy bars on a trailing 0–100% axis (web `accuracyColor`,
///   gold for a 100% full combo) and the score line on the leading axis, paged like the
///   Rank History chart; tapping a bar shows that score's detail row;
/// - the best five scores as separate rows, the best one highlighted and bold;
/// - "View all scores" (more than five) expands every score in place, so there is no
///   separate history page; `/songs/:id/:instrument/history` deep links open this page
///   scrolled here with the list expanded (`PlayerHistoryScreen`).
struct SongScoreHistorySection: View {
    let entries: [ScoreHistoryEntry]
    /// Visible charted instruments in display order (the selector's pool).
    let pool: [Instrument]
    let keyboardIcon: Bool
    @Binding var instrument: Instrument?
    @Binding var expanded: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    /// Scroll target id for deep links.
    static let anchor = "fst.song-detail.history"

    private var available: [Instrument] { SongScoreHistoryModel.instruments(with: entries, in: pool) }

    private var shown: Instrument? {
        SongScoreHistoryModel.resolvedInstrument(preferred: instrument, available: available)
    }

    var body: some View {
        if let shown {
            let rows = SongScoreHistoryModel.chronological(entries, instrument: shown)
            let list = SongScoreHistoryModel.bestFirst(rows, limit: expanded ? nil : SongScoreHistoryModel.listLimit)
            VStack(alignment: .leading, spacing: 8) {
                FestivalSectionHeader("Score History", subtitle: "Select a bar to see more score details.")
                    .padding(.horizontal, 4)
                VStack(spacing: 12) {
                    InstrumentSelector(
                        instruments: available,
                        required: Binding(get: { shown }, set: { instrument = $0 }),
                        look: .graph, keyboardIcon: keyboardIcon,
                        identifier: "fst.song-detail.history.instrument"
                    )
                    ScoreHistoryChart(
                        rows: rows, instrument: shown,
                        motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion)
                    )
                    .id(shown)
                }
                .padding(14)
                .festivalGlass(.card, cornerRadius: 16)
                VStack(spacing: 6) {
                    ForEach(Array(list.enumerated()), id: \.offset) { index, entry in
                        ScoreHistoryListRow(entry: entry, isBest: index == 0)
                            .accessibilityIdentifier("fst.song-detail.history.row.\(index)")
                    }
                }
                if rows.count > SongScoreHistoryModel.listLimit {
                    Button {
                        withAnimation(systemReduceMotion || appReduceMotion ? nil : .easeOut(duration: 0.25)) {
                            expanded.toggle()
                        }
                    } label: {
                        PurpleActionLabel(title: expanded ? "Show top scores" : "View all scores")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fst.song-detail.history.view-all")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.anchor)
        }
    }
}

// MARK: - Chart

/// Accuracy bars and the score line for one instrument, one page at a time.
private struct ScoreHistoryChart: View {
    let rows: [ScoreHistoryEntry]
    let instrument: Instrument
    let motion: ChartMotion

    @State private var chartWidth: CGFloat = 0
    /// Index of the oldest visible row; nil shows the newest page.
    @State private var start: Int?
    @State private var selectedIndex: Int?

    struct Point: Identifiable, Equatable {
        /// Series index: the x value, so paging slides the window without moving points.
        let id: Int
        let label: String
        let score: Double
        let accuracy: Double
        let gold: Bool
        let entry: ScoreHistoryEntry
    }

    private var points: [Point] {
        rows.enumerated().map { index, entry in
            Point(
                id: index, label: Self.dateLabel(entry), score: Double(entry.newScore),
                accuracy: SongScoreHistoryModel.accuracyPercent(entry),
                gold: SongScoreHistoryModel.isGold(entry), entry: entry
            )
        }
    }

    private var paging: RankHistoryPaging {
        let plot = Double(max(0, chartWidth - 96))
        return RankHistoryPaging(
            count: rows.count, pageSize: chartWidth > 0 ? RankHistoryPaging.pageSize(forPlotWidth: plot) : rows.count
        )
    }

    private var first: Int { paging.clamp(start ?? paging.latestStart) }

    /// Top of the shared y scale (score axis), with the web's headroom.
    private var top: Double { max(1, (points.map(\.score).max() ?? 0) * 1.1) }

    var body: some View {
        let all = points
        let range = paging.visibleRange(from: first)
        let visible = Array(all[range])
        VStack(spacing: 10) {
            chart(all, range: range)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { width in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { chartWidth = width }
                }
            legend(visible)
            if paging.needsPagination { pager }
            if let selectedIndex, all.indices.contains(selectedIndex) {
                let selected = all[selectedIndex]
                ScoreHistoryListRow(entry: selected.entry, isBest: false)
                    .transition(.opacity)
                    .accessibilityIdentifier("fst.song-detail.history.detail")
            }
        }
        .animation(motion.animation, value: selectedIndex)
    }

    private func chart(_ data: [Point], range: Range<Int>) -> some View {
        let top = top
        let barWidth = max(8, (chartWidth - 96) / CGFloat(max(1, range.count)) * 0.85)
        let visible = data.filter { range.contains($0.id) }
        return Chart(data) { point in
            BarMark(x: .value("Date", point.id), y: .value("Accuracy", point.accuracy / 100 * top), width: .fixed(barWidth))
                .foregroundStyle(point.gold ? BrandTokens.gold : Self.accuracyColor(point.accuracy))
                .cornerRadius(4)
                .opacity(selectedIndex == nil || selectedIndex == point.id ? 1 : 0.55)
            LineMark(x: .value("Date", point.id), y: .value("Score", point.score), series: .value("Series", "Score"))
                .foregroundStyle(RankHistoryCharts.rankLineColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", point.id), y: .value("Score", point.score))
                .foregroundStyle(RankHistoryCharts.rankLineColor)
                .symbolSize(30)
        }
        .chartYScale(domain: 0 ... top)
        .chartXScale(domain: Double(range.lowerBound) - 0.5 ... Double(max(range.lowerBound + 1, range.upperBound)) - 0.5)
        .chartPlotStyle { $0.clipped() }
        .chartXSelection(value: selection)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(BrandTokens.glassBorder)
                AxisValueLabel {
                    if let score = value.as(Double.self) {
                        Text(score >= 1000 ? "\(Int((score / 1000).rounded()))k" : "\(Int(score))")
                            .foregroundStyle(FestivalText.primary)
                    }
                }
            }
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100].map { Double($0) / 100 * top }) { value in
                AxisValueLabel {
                    if let y = value.as(Double.self) {
                        Text("\(Int((y / top * 100).rounded()))%").foregroundStyle(FestivalText.primary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: visible.map(\.id)) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self), data.indices.contains(index) {
                        Text(data[index].label).foregroundStyle(FestivalText.primary)
                    }
                }
            }
        }
        .frame(height: 220)
        .accessibilityLabel("\(instrument.label) score history chart")
        .accessibilityValue(
            "\(rows.count) scores, best \((rows.map(\.newScore).max() ?? 0).formatted())"
        )
        .accessibilityIdentifier("fst.song-detail.history.chart")
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { drag in
                let dx = drag.translation.width
                guard paging.needsPagination, abs(dx) > 50, abs(dx) > abs(drag.translation.height) else { return }
                move(to: dx < 0 ? paging.forwardPage(from: first) : paging.backPage(from: first))
            }
        )
    }

    /// Web legend: accuracy gradient (when any non-gold bar), gold "Accuracy (FC)" (when
    /// any gold bar), and the score line.
    private func legend(_ data: [Point]) -> some View {
        HStack(spacing: 16) {
            if data.contains(where: { !$0.gold }) {
                swatch(AnyShapeStyle(LinearGradient(
                    colors: [Self.accuracyColor(0), Self.accuracyColor(100)], startPoint: .leading, endPoint: .trailing
                )), "Accuracy")
            }
            if data.contains(where: \.gold) {
                swatch(AnyShapeStyle(BrandTokens.gold), "Accuracy (FC)")
            }
            HStack(spacing: 6) {
                ZStack(alignment: .trailing) {
                    Rectangle().fill(RankHistoryCharts.rankLineColor).frame(width: 18, height: 2)
                    Circle().fill(RankHistoryCharts.rankLineColor).frame(width: 6, height: 6).offset(x: 3)
                }
                .frame(width: 24, height: 12, alignment: .leading)
                Text("Score")
            }
        }
        .font(.subheadline)
        .foregroundStyle(FestivalText.primary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: bars show accuracy, the line shows score")
    }

    private func swatch(_ style: AnyShapeStyle, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(style).frame(width: 16, height: 12)
            Text(title)
        }
    }

    private var pager: some View {
        let paging = paging
        let first = first
        return HStack(spacing: 12) {
            pagerButton("chevron.left.2", "Back one page", enabled: paging.canGoBack(from: first)) {
                move(to: paging.backPage(from: first))
            }
            pagerButton("chevron.left", "Back one entry", enabled: paging.canGoBack(from: first)) {
                move(to: paging.backEntry(from: first))
            }
            Spacer(minLength: 0)
            pagerButton("chevron.right", "Forward one entry", enabled: paging.canGoForward(from: first)) {
                move(to: paging.forwardEntry(from: first))
            }
            pagerButton("chevron.right.2", "Forward one page", enabled: paging.canGoForward(from: first)) {
                move(to: paging.forwardPage(from: first))
            }
        }
    }

    private func pagerButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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
    }

    private func move(to index: Int) {
        withAnimation(motion.animation) {
            start = index == paging.latestStart ? nil : index
            selectedIndex = nil
        }
    }

    /// Tap selection snapped to the nearest bar (numeric x selection yields a Double).
    private var selection: Binding<Double?> {
        Binding(
            get: { selectedIndex.map(Double.init) },
            set: { value in
                guard let value else { return }
                let index = Int(value.rounded())
                if points.indices.contains(index) { selectedIndex = index }
            }
        )
    }

    /// Web `accuracyColor`: red (220,40,40) → green (46,204,113) over 0–100%.
    static func accuracyColor(_ percent: Double) -> Color {
        let t = min(max(percent / 100, 0), 1)
        return Color(.sRGB, red: (220 * (1 - t) + 46 * t) / 255, green: (40 * (1 - t) + 204 * t) / 255,
                     blue: (40 * (1 - t) + 113 * t) / 255)
    }

    /// Web `dateLabel`: `M/D/YY` in local time.
    static func dateLabel(_ entry: ScoreHistoryEntry) -> String {
        guard let date = entry.displayDate else { return "—" }
        let parts = Calendar.current.dateComponents([.month, .day, .year], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)/\(String(parts.year ?? 0).suffix(2))"
    }
}

// MARK: - List row

/// One score beneath the chart (web score list card with `LeaderboardEntry`): date,
/// season, score and the shared accuracy badge; the best score purple and bold.
struct ScoreHistoryListRow: View {
    let entry: ScoreHistoryEntry
    let isBest: Bool

    private var dateText: String {
        guard let date = entry.displayDate else { return "\u{2014}" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.body.weight(isBest ? .bold : .regular))
                    .foregroundStyle(FestivalText.primary)
                if let season = entry.season {
                    Text("Season \(season)")
                        .font(.caption)
                        .foregroundStyle(FestivalText.primary)
                }
            }
            Spacer(minLength: 8)
            Text(entry.newScore.formatted())
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(FestivalText.primary)
            if let accuracy = entry.accuracy {
                let fullCombo = entry.isFullCombo == true
                Text("\(ScoreFormatting.accuracy(accuracy))%")
                    .font(fullCombo ? .body.bold().italic() : .body)
                    .foregroundStyle(fullCombo ? BrandTokens.gold : FestivalText.primary)
                    .frame(width: 76, height: 24)
                    .background(fullCombo ? Color.clear : ScoreHistoryChart.accuracyColor(accuracy / 10_000).opacity(0.25),
                                in: GoldSkewBadgeShape(skewed: fullCombo))
                    .overlay {
                        if fullCombo { GoldSkewBadgeShape(skewed: true).stroke(BrandTokens.gold, lineWidth: 2) }
                    }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            if isBest {
                shape.fill(Color(.sRGB, red: 75 / 255, green: 15 / 255, blue: 99 / 255, opacity: 0.75))
                    .overlay(shape.stroke(BrandTokens.accentPurple.opacity(0.5), lineWidth: 1))
            } else {
                Color.clear.festivalGlass(.card, cornerRadius: 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(dateText), score \(entry.newScore.formatted())"
                + (entry.accuracy.map { ", accuracy \(ScoreFormatting.accuracy($0)) percent" } ?? "")
                + (entry.isFullCombo == true ? ", full combo" : "")
                + (isBest ? ", best score" : "")
        )
    }
}
