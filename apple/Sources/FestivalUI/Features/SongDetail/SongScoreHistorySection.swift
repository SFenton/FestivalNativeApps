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
/// - the best five scores as entries under the graph in the same group card (like the
///   Rivals cards, issue #381), the best one highlighted and bold;
/// - "View All Scores" (more than five, web `GraphCard` `viewAllLabel`) opens the
///   separate, sortable Score History page (``PlayerHistoryScreen``, issue #324):
///   pushed on iPhone, in the trailing pane where Song Detail splits.
struct SongScoreHistorySection: View {
    /// The song (the View All Scores route).
    let song: Song
    let entries: [ScoreHistoryEntry]
    /// Visible charted instruments in display order (the selector's pool).
    let pool: [Instrument]
    @Binding var instrument: Instrument?
    /// The page (viewport) width: list rows show the season from 520 pt, like the web's
    /// `QUERY_SHOW_SEASON` media query (`ScoreRowSeasonPolicy`, issue #32).
    var viewportWidth: CGFloat = 0
    /// The catalogue's current season, whose pill is inverted.
    var currentSeason: Int?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    /// Instrument the graph and list show; trails the selector while a swap fades (#31).
    @State private var displayed: Instrument?
    /// Opacity of the graph and best-scores list during an instrument swap.
    @State private var contentOpacity: Double = 1
    /// The running fade-out → swap → fade-in sequence, cancelled by a newer choice.
    @State private var swap: Task<Void, Never>?
    /// The card's measured content size (natural, before any pin).
    @State private var cardSize: CGSize = .zero
    /// The card height held while a swap runs, so the card keeps its size.
    @State private var pinnedHeight: CGFloat?

    /// Section identifier and scroll target (Quick Links).
    static let anchor = "fst.song-detail.history"

    private var available: [Instrument] { SongScoreHistoryModel.instruments(with: entries, in: pool) }

    private var shown: Instrument? {
        SongScoreHistoryModel.resolvedInstrument(preferred: instrument, available: available)
    }

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        if let shown {
            let current = displayed.flatMap { available.contains($0) ? $0 : nil } ?? shown
            let rows = SongScoreHistoryModel.chronological(entries, instrument: current)
            let list = SongScoreHistoryModel.bestFirst(rows, limit: SongScoreHistoryModel.listLimit)
            // One group card for the graph and the best scores, like Rivals (#381),
            // ending with View All Scores inside it (view-all-cta R1, #382).
            FestivalGlassSection(
                "Score History", subtitle: "Select a bar to see more score details.",
                rows: .flush(separatorInset: 14)
            ) {
                VStack(spacing: 12) {
                    InstrumentSelector(
                        instruments: available,
                        required: Binding(get: { shown }, set: { instrument = $0 }),
                        look: .graph, keyboardIcon: song.usesKeyboardIcon,
                        identifier: "fst.song-detail.history.instrument"
                    )
                    ScoreHistoryChart(
                        rows: rows, instrument: current, chartWidth: cardSize.width,
                        reservesPager: SongScoreHistoryModel.reservesPager(
                            entries, instruments: available, chartWidth: Double(cardSize.width)
                        ),
                        motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion),
                        currentSeason: currentSeason
                    )
                    .id(current)
                    .opacity(contentOpacity)
                }
                .onGeometryChange(for: CGSize.self, of: { CGSize(width: $0.size.width.rounded(), height: $0.size.height.rounded()) }) { size in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { cardSize = size }
                }
                .frame(minHeight: pinnedHeight, alignment: .top)
                .padding(14)
                // The tapped bar's detail row keeps its own card inside the graph.
                .environment(\.festivalGroupedRow, false)
                ForEach(Array(list.enumerated()), id: \.offset) { index, entry in
                    ScoreHistoryListRow(
                        entry: entry, isBest: index == 0,
                        seasonColumn: ScoreRowSeasonPolicy.showsColumn(
                            .historyList, width: Double(viewportWidth)
                        ),
                        currentSeason: currentSeason
                    )
                    .opacity(contentOpacity)
                    .accessibilityIdentifier("fst.song-detail.history.row.\(index)")
                }
            } action: {
                if rows.count > SongScoreHistoryModel.listLimit {
                    // Pushes the Score History page; opens it in the trailing pane
                    // where Song Detail can split (view-all-cta R4 label first).
                    ListDetailLink(value: AppRoute.playerHistory(song, current)) {
                        PurpleActionLabel(title: "View All Scores")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        PurpleActionName.spoken("View All Scores", card: "\(current.label) Score History")
                    )
                    .accessibilityIdentifier("fst.song-detail.history.view-all")
                    .opacity(contentOpacity)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.anchor)
            .onAppear {
                if displayed == nil { displayed = shown }
            }
            .onChange(of: shown) { old, new in
                switchInstrument(to: new, from: displayed ?? old)
            }
            .onDisappear {
                swap?.cancel()
                swap = nil
            }
        }
    }

    // MARK: - Instrument swap

    /// Fade the graph and list out, swap to `target`, then fade them back in, keeping the
    /// card's height for the whole swap; a newer choice cancels the running swap (HIG
    /// Motion: let people cancel animations rather than wait). Instant under Reduce Motion.
    ///
    /// - Parameters:
    ///   - target: The selector's new instrument.
    ///   - from: The instrument the graph shows now.
    private func switchInstrument(to target: Instrument, from: Instrument) {
        let still = Transaction(animation: nil).disablingAnimations()
        switch ScoreHistorySwap.plan(displayed: from, target: target, reduceMotion: reduceMotion) {
        case .none:
            return
        case .settle:
            swap?.cancel()
            swap = nil
            withAnimation(.easeOut(duration: ScoreHistorySwap.fadeInSeconds)) { contentOpacity = 1 }
            withTransaction(still) { pinnedHeight = nil }
        case .instant:
            swap?.cancel()
            swap = nil
            withTransaction(still) {
                displayed = target
                contentOpacity = 1
                pinnedHeight = nil
            }
        case .fade:
            swap?.cancel()
            if pinnedHeight == nil, cardSize.height > 0 { pinnedHeight = cardSize.height }
            swap = Task { @MainActor in
                withAnimation(.easeIn(duration: ScoreHistorySwap.fadeOutSeconds)) { contentOpacity = 0 }
                try? await Task.sleep(for: .seconds(ScoreHistorySwap.fadeOutSeconds))
                guard !Task.isCancelled else { return }
                withTransaction(still) { displayed = target }
                // Every instrument's rows are already in memory: fade in once the new
                // graph has had a pass to lay out.
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: ScoreHistorySwap.fadeInSeconds)) { contentOpacity = 1 }
                try? await Task.sleep(for: .seconds(ScoreHistorySwap.fadeInSeconds))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: ScoreHistorySwap.fadeInSeconds)) { pinnedHeight = nil }
                swap = nil
            }
        }
    }
}

private extension Transaction {
    /// This transaction with implicit animations (`.animation(_:value:)`) disabled too.
    func disablingAnimations() -> Transaction {
        var copy = self
        copy.disablesAnimations = true
        return copy
    }
}

// MARK: - Chart

/// Accuracy bars and the score line for one instrument, one page at a time.
private struct ScoreHistoryChart: View {
    let rows: [ScoreHistoryEntry]
    let instrument: Instrument
    /// The card's measured width, shared across instruments so a new graph opens on its
    /// final page size (and pager) instead of resizing on its first frame.
    let chartWidth: CGFloat
    /// Keep the pager row's space even when this instrument fits one page.
    let reservesPager: Bool
    let motion: ChartMotion
    /// The catalogue's current season, for the tapped bar's season pill.
    let currentSeason: Int?

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
        SongScoreHistoryModel.paging(count: rows.count, chartWidth: Double(chartWidth))
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
            legend(visible)
            if paging.needsPagination {
                pager
            } else if reservesPager {
                pager.hidden().accessibilityHidden(true)
            }
            if let selectedIndex, all.indices.contains(selectedIndex) {
                let selected = all[selectedIndex]
                // The tapped bar's row always carries the season (web `renderDetailCard`).
                ScoreHistoryListRow(
                    entry: selected.entry, isBest: false,
                    seasonColumn: ScoreRowSeasonPolicy.showsColumn(.historyDetail, width: 0),
                    currentSeason: currentSeason
                )
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
        .barChartDateAxis(values: visible.map(\.id)) { data.indices.contains($0) ? data[$0].label : nil }
        .chartPlotFrameReporter()
        .frame(height: 220)
        // One element: unlabelled, its bars read their plotted ranges ("0 to 0.2") and,
        // being selectable, were audited as 11–19 pt controls in an AX5 iPhone Duo pane
        // (Lane A11Y3). The rows below read every score; the chart summarizes them.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(instrument.label) score history chart")
        .accessibilityValue(
            "\(rows.count) scores, best \((rows.map(\.newScore).max() ?? 0).formatted())"
        )
        .accessibilityIdentifier("fst.song-detail.history.chart")
        .chartAxisElements(ChartAxisLabels(
            leading: "Score scale, 0 to \(top >= 1000 ? "\(Int((top / 1000).rounded()))k" : "\(Int(top))")",
            trailing: "Accuracy scale, 0% to 100%",
            bottom: "Dates, " + ChartAxisLabels.span(visible.first?.label, visible.last?.label)
        ))
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
        // Static text, not a control: inside the swipe-to-page chart the audit
        // otherwise judged it an 18 pt-tall interactive element ("Hit area is too small").
        .accessibilityAddTraits(.isStaticText)
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
            pagerButton("chevron.backward.2", "Back one page", enabled: paging.canGoBack(from: first)) {
                move(to: paging.backPage(from: first))
            }
            pagerButton("chevron.backward", "Back one entry", enabled: paging.canGoBack(from: first)) {
                move(to: paging.backEntry(from: first))
            }
            Spacer(minLength: 0)
            pagerButton("chevron.forward", "Forward one entry", enabled: paging.canGoForward(from: first)) {
                move(to: paging.forwardEntry(from: first))
            }
            pagerButton("chevron.forward.2", "Forward one page", enabled: paging.canGoForward(from: first)) {
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
/// optional season pill, score and the shared accuracy badge; the best score purple
/// and bold. Its own card on the Score History page; a flat entry inside the song
/// page's grouped Score History card (``EnvironmentValues/festivalGroupedRow``, #381).
struct ScoreHistoryListRow: View {
    let entry: ScoreHistoryEntry
    let isBest: Bool
    /// Show the season pill before the score; callers decide with
    /// `ScoreRowSeasonPolicy` (issue #32: the web hides it below 520 px).
    var seasonColumn = false
    /// The catalogue's current season, whose pill is inverted.
    var currentSeason: Int?

    private var season: Int? {
        guard seasonColumn, let season = entry.season, season > 0 else { return nil }
        return season
    }

    private var dateText: String {
        guard let date = entry.displayDate else { return "\u{2014}" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.festivalGroupedRow) private var grouped

    var body: some View {
        // Accessibility sizes stack the date (and season) over the score and accuracy
        // (HIG Typography: "consider stacking text above secondary items"; leaderboard-row
        // R2, as `RankingRowLayout`): one line squeezed "850,000" into "85 / 0, / 00 / 0"
        // on an iPhone at AX5 (#385). Standard sizes keep the web's single-line row.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    dateLabel(stacked: true)
                    if let season {
                        ScoreSeasonPill(season: season, current: season == currentSeason)
                    }
                    // Score and accuracy share a line when it fits, else stack.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            scoreLabel(stacked: true)
                            Spacer(minLength: 8)
                            accuracyBadge(stacked: true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            scoreLabel(stacked: true)
                            accuracyBadge(stacked: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 10) {
                    dateLabel(stacked: false)
                    Spacer(minLength: 8)
                    if seasonColumn {
                        ScoreSeasonPill(season: season, current: season != nil && season == currentSeason)
                    }
                    scoreLabel(stacked: false)
                    accuracyBadge(stacked: false)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            if grouped {
                // Inside the Score History group card: the best score is a flat purple
                // band between the hairlines, other rows draw nothing (issue #381).
                if isBest { Rectangle().fill(RankingRowSurface.playerFill) }
            } else if isBest {
                shape.fill(Color(.sRGB, red: 75 / 255, green: 15 / 255, blue: 99 / 255, opacity: 0.75))
                    .overlay(shape.stroke(BrandTokens.accentPurple.opacity(0.5), lineWidth: 1))
            } else {
                Color.clear.festivalCard(cornerRadius: 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(dateText)"
                + (season.map { ", " + ScoreSeasonPill.spokenLabel(season: $0, current: $0 == currentSeason).lowercased() } ?? "")
                + ", score \(entry.newScore.formatted())"
                + (entry.accuracy.map { ", accuracy \(ScoreFormatting.accuracy($0)) percent" } ?? "")
                + (entry.isFullCombo == true ? ", full combo" : "")
                + (isBest ? ", best score" : "")
        )
    }

    /// The score's date; wraps at word boundaries at accessibility sizes, otherwise one
    /// line that may shrink a little.
    ///
    /// - Parameter stacked: Accessibility-size layout.
    /// - Returns: The date text.
    private func dateLabel(stacked: Bool) -> some View {
        Text(dateText)
            .font(.body.weight(isBest ? .bold : .regular))
            .foregroundStyle(FestivalText.primary)
            .lineLimit(stacked ? nil : 1)
            .minimumScaleFactor(stacked ? 1 : 0.75)
            .fixedSize(horizontal: false, vertical: stacked)
    }

    /// The score, kept whole on one line (leaderboard-row R8): at accessibility sizes it
    /// scales down rather than break between digits.
    ///
    /// - Parameter stacked: Accessibility-size layout.
    /// - Returns: The score text.
    private func scoreLabel(stacked: Bool) -> some View {
        Text(entry.newScore.formatted())
            .font(.body.weight(.semibold).monospacedDigit())
            .foregroundStyle(FestivalText.primary)
            .lineLimit(1)
            .minimumScaleFactor(stacked ? 0.5 : 1)
    }

    /// The shared accuracy badge (gold skewed outline for a full combo).
    ///
    /// - Parameter stacked: Accessibility-size layout: the badge grows around its text.
    /// - Returns: The badge, or nothing for an entry without accuracy.
    @ViewBuilder
    private func accuracyBadge(stacked: Bool) -> some View {
        if let accuracy = entry.accuracy {
            let fullCombo = entry.isFullCombo == true
            Text("\(ScoreFormatting.accuracy(accuracy))%")
                .font(fullCombo ? .body.bold().italic() : .body)
                .foregroundStyle(fullCombo ? BrandTokens.gold : FestivalText.primary)
                // A fixed 76 × 24 pt pill cut "95.5%" to "9…" at AX5 (iPad audit, Lane
                // A11Y3); accessibility sizes let it grow around the text.
                .lineLimit(1)
                .padding(.horizontal, stacked ? 8 : 0)
                .frame(width: stacked ? nil : 76, height: stacked ? nil : 24)
                .frame(minWidth: stacked ? 76 : nil, minHeight: stacked ? 24 : nil)
                .fixedSize(horizontal: stacked, vertical: stacked)
                .background(fullCombo ? Color.clear : ScoreHistoryChart.accuracyColor(accuracy / 10_000).opacity(0.25),
                            in: GoldSkewBadgeShape(skewed: fullCombo))
                .overlay {
                    if fullCombo { GoldSkewBadgeShape(skewed: true).stroke(BrandTokens.gold, lineWidth: 2) }
                }
        }
    }
}
