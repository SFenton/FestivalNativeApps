import SwiftUI
import Charts
import FestivalCore
import FestivalDesign

// MARK: - songinfo-chart

/// Ported from `pages/songinfo/firstRun/demo/ChartDemo.tsx`: accuracy bars (gold when full
/// combo, an accuracy-ramp tint otherwise) with each bar's score annotated above it.
struct FirstRunSongInfoChartDemo: View {
    var body: some View {
        VStack(spacing: 10) {
            Chart(FirstRunDemoPool.scoreHistory) { point in
                BarMark(x: .value("Date", point.label), y: .value("Accuracy", point.accuracy))
                    .foregroundStyle(firstRunAccuracyTint(point.accuracy, isFullCombo: point.isFullCombo))
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text(point.score.formatted())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(FestivalText.primary)
                    }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 150)
            legend
        }
        .padding(14)
        .festivalCard(cornerRadius: 16)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("Accuracy", BrandTokens.accentBlue)
            legendItem("Full Combo", BrandTokens.gold)
        }
        .font(.caption2)
        .foregroundStyle(FestivalText.deemphasized)
    }

    private func legendItem(_ label: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 10, height: 10)
            Text(label)
        }
    }
}

// MARK: - songinfo-bar-select

/// Ported from `pages/songinfo/firstRun/demo/BarSelectDemo.tsx`: the same chart with one bar
/// selected (a purple selection stroke) and its details in a card below. As on the web, every
/// 2.5 s the card fades out over 300 ms, the selection moves to the next bar and the card
/// fades back in.
struct FirstRunSongInfoBarSelectDemo: View {
    private static let barWidth: CGFloat = 28
    private var points: [FirstRunDemoPool.ScorePoint] { FirstRunDemoPool.scoreHistory }
    private var selected: FirstRunDemoPool.ScorePoint { points[selectedIndex % points.count] }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex = 0
    @State private var fading: Set<Int> = []

    var body: some View {
        VStack(spacing: 10) {
            Chart(points) { point in
                BarMark(
                    x: .value("Date", point.label), y: .value("Accuracy", point.accuracy),
                    width: .fixed(Self.barWidth)
                )
                .foregroundStyle(firstRunAccuracyTint(point.accuracy, isFullCombo: point.isFullCombo))
                .cornerRadius(4)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 120)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    selectionStroke(proxy: proxy, geometry: geometry)
                }
            }
            HStack(spacing: 16) {
                Text(selected.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                Spacer(minLength: 0)
                Text(selected.score.formatted())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(FestivalText.primary)
                Text("\(Int(selected.accuracy))%")
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
                if selected.isFullCombo {
                    FirstRunStar(gold: true, size: 16)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(BrandTokens.accentPurple.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            .firstRunSwapRow(0, key: selectedIndex)
        }
        .padding(14)
        .festivalCard(cornerRadius: 16)
        .environment(\.firstRunFadingRows, fading)
        .accessibilityHidden(true)
        .firstRunDemoTicker(every: FirstRunDemoTiming.barSelectInterval) { await swap() }
    }

    /// The selected bar's purple outline, placed from the chart's own scales.
    @ViewBuilder
    private func selectionStroke(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let plot = proxy.plotFrame,
           let x = proxy.position(forX: selected.label),
           let top = proxy.position(forY: selected.accuracy),
           let bottom = proxy.position(forY: 0.0) {
            let frame = geometry[plot]
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(BrandTokens.accentPurple, lineWidth: 2)
                .frame(width: Self.barWidth + 4, height: max(0, bottom - top) + 4)
                .position(x: frame.minX + x, y: frame.minY + (top + bottom) / 2)
                // The selection jumps, as on the web; it never slides between bars.
                .transaction { $0.animation = nil }
        }
    }

    private func swap() async {
        await FirstRunDemoSwap.run(
            reduceMotion: reduceMotion, seconds: FirstRunDemoTiming.barSelectFadeSeconds,
            fadeOut: { fading = [0] },
            update: { selectedIndex = (selectedIndex + 1) % points.count },
            fadeIn: { fading = [] }
        )
    }
}

// MARK: - songinfo-view-all

/// Ported from `pages/songinfo/firstRun/demo/ViewAllDemo.tsx`: Song Detail's real Score
/// History rows (``ScoreHistoryListRow``), the last row faded like the web's bottom mask, and
/// the page's pulsing **View All Scores** action below.
struct FirstRunSongInfoViewAllDemo: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(FirstRunDemoPool.ownHistory.enumerated()), id: \.offset) { index, entry in
                ScoreHistoryListRow(entry: entry, isBest: index == 0)
                    .opacity(index == FirstRunDemoPool.ownHistory.count - 1 ? 0.45 : 1)
                    .firstRunStagger(index)
            }
            FirstRunViewAllRow(title: "View All Scores")
                .firstRunStagger(FirstRunDemoPool.ownHistory.count)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - songinfo-top-scores

/// Ported from `pages/songinfo/firstRun/demo/TopScoresDemo.tsx`: the instrument's top leaderboard
/// entries with a pulsing "View full leaderboard" row.
struct FirstRunSongInfoTopScoresDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FirstRunInstrumentHeader(instrument: .lead)
                .firstRunStagger(0)
            // The Song Detail card's real rows (`SongLeaderboardEntryRow`, operator batch 7).
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(FirstRunDemoPool.topScores.enumerated()), id: \.element.id) { index, entry in
                    SongLeaderboardEntryRow(entry: LeaderboardEntry(
                        accountId: "fre-\(entry.rank)", displayName: entry.name,
                        score: entry.score, rank: entry.rank,
                        accuracy: Double(entry.accuracyPercent) * 10_000,
                        isFullCombo: entry.isFullCombo, stars: entry.isFullCombo ? 6 : 5,
                        season: nil, difficulty: nil
                    ))
                    .padding(.vertical, 11)
                    .firstRunStagger(index + 1)
                    if index < FirstRunDemoPool.topScores.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .festivalCard(cornerRadius: 16)
            FirstRunViewAllRow(title: "View full leaderboard")
                .firstRunStagger(FirstRunDemoPool.topScores.count + 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - songinfo-paths

/// Ported from `pages/songinfo/firstRun/demo/PathPreviewDemo.tsx`: the instrument selector,
/// difficulty selector, and a static path preview placeholder (the web loads a real chart image
/// over the network; a demo never does).
struct FirstRunSongInfoPathsDemo: View {
    private let instruments: [Instrument] = [.lead, .bass, .drums, .vocals]
    private let difficulties = ["Easy", "Medium", "Hard", "Expert"]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(instruments, id: \.self) { instrument in
                    InstrumentIcon(instrument, size: 28)
                        .padding(6)
                        .background(
                            instrument == .lead ? BrandTokens.accentBlue.opacity(0.3) : .clear,
                            in: Circle()
                        )
                }
            }
            HStack(spacing: 8) {
                ForEach(difficulties, id: \.self) { difficulty in
                    Text(difficulty)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            difficulty == "Expert" ? FestivalText.primary : FestivalText.primary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            difficulty == "Expert" ? BrandTokens.accentPurple.opacity(0.35) : BrandTokens.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
            }
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BrandTokens.surfaceMuted)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.title2)
                        Text("Path Preview").font(.caption)
                    }
                    .foregroundStyle(FestivalText.primary)
                )
                .frame(maxWidth: .infinity, minHeight: 90)
        }
        .padding(14)
        .festivalCard(cornerRadius: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - Item Shop action (songinfo-shop-button / -new-in-shop / -leaving-tomorrow)

/// Ported from `pages/songinfo/firstRun/demo/{ShopButtonDemo,LeavingTomorrowButtonDemo}.tsx`
/// ("matches the production Song Info header pill/circle exactly"): Song Detail's real Item
/// Shop action beside a catalogue song's header. Like the page (and the web demo's
/// `settings.disableShopHighlighting` gate), the disc breathes green, gold or red only while
/// Shop highlighting is on, and the action is a plain titled button otherwise or in the
/// vertical section bar (``SongDetailShopActionStyle``).
struct FirstRunSongInfoShopPillDemo: View {
    enum Tone { case shop, new, leaving }
    let tone: Tone

    @AppStorage("fst.settings.disableShopHighlighting") private var highlightingDisabled = false
    @Environment(\.deviceLayout) private var deviceLayout

    private var statusTone: ShopStatusTone {
        switch tone {
        case .shop: .inShop
        case .new: .new
        case .leaving: .leaving
        }
    }

    var body: some View {
        FirstRunCatalogueSongs(count: 1) { songs, session in
            HStack(spacing: 12) {
                if let song = songs.first {
                    FirstRunSongArt(song: song, session: session, size: 56)
                    // Song Details' shared header column (song-header R1).
                    SongHeaderText(
                        title: song.title, artist: song.artist, titleFont: .headline, spacing: 2
                    ) { EmptyView() }
                    .firstRunRedacted(song)
                }
                Spacer(minLength: 8)
                action
            }
            .padding(14)
            .festivalCard(cornerRadius: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var action: some View {
        let resolved = SongDetailShopActionStyle.resolve(
            tone: highlightingDisabled ? nil : statusTone, chrome: deviceLayout.sectionChrome
        )
        switch resolved {
        case let .breathing(tone):
            SongDetailShopGlyph(tone: tone)
        case .titled:
            Label("Item Shop", systemImage: "bag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                // The system bar's glass button, which the page's titled toolbar item gets.
                .festivalGlassCapsule(.control)
        }
    }
}
