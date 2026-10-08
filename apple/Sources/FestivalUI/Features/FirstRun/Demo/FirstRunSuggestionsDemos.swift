import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - suggestions-category-card

/// Ported from `pages/suggestions/firstRun/demo/CategoryCardDemo.tsx`: one themed suggestion
/// card. As on the web, every 5 s the card fades out (8 pt drop), moves to the next of the
/// web's four category templates with the next songs, and fades back in.
struct FirstRunSuggestionsCategoryCardDemo: View {
    /// Songs each card shows.
    static let songsPerCard = 2

    @FirstRunReduceMotion private var reduceMotion
    @State private var template = 0
    @State private var fading: Set<Int> = []

    var body: some View {
        FirstRunCatalogueSongs(count: Self.songsPerCard * Self.templates.count) { pool, session in
            let songs = Self.window(of: pool, template: template)
            let category = Self.templates[template].category(songs)
            FirstRunSuggestionCard(category: category, session: session)
                .firstRunSwapRow(0, rise: 8)
        }
        .environment(\.firstRunFadingRows, fading)
        .accessibilityHidden(true)
        .firstRunDemoTicker { await swap() }
    }

    private func swap() async {
        await FirstRunDemoSwap.run(
            reduceMotion: reduceMotion,
            fadeOut: { fading = [0] },
            update: { template = (template + 1) % Self.templates.count },
            fadeIn: { fading = [] }
        )
    }

    /// The songs a template shows: the pool window starting at `template × songsPerCard`,
    /// as the web's `start = templateIdx * MAX_DEMO_SONGS`.
    static func window(of pool: [Song], template: Int) -> [Song] {
        guard !pool.isEmpty else { return [] }
        let start = template * songsPerCard
        return (0..<songsPerCard).map { pool[(start + $0) % pool.count] }
    }

    /// One of the web's `TEMPLATES`.
    struct Template: Sendable {
        let key: String
        let title: String
        let description: String
        let type: SuggestionCategoryType
        let instrument: Instrument?
        let item: @Sendable (Song, Int) -> SuggestionSongItem

        func category(_ songs: [Song]) -> SuggestionCategory {
            SuggestionCategory(
                key: key, title: title, description: description, type: type, instrument: instrument,
                songs: songs.enumerated().map { item($1, $0) }
            )
        }
    }

    static let templates: [Template] = [
        Template(
            key: "unfc_guitar", title: "Finish the Lead FCs",
            description: "Play these songs again on Lead and grab an FC!", type: .nearFC, instrument: .lead
        ) { song, index in
            SuggestionSongItem(song: song, instrument: .lead, percent: Double(100 - index * 2))
        },
        Template(
            key: "pct_push_bass", title: "Percentile Push: Bass",
            description: "Replay these Bass songs to jump to the next percentile bracket.",
            type: .percentilePush, instrument: .bass
        ) { song, index in
            SuggestionSongItem(song: song, instrument: .bass, percentileDisplay: "Top \(3 + index)%")
        },
        Template(
            key: "near_fc_any", title: "FC These Next!",
            description: "If you can get gold stars, you can FC it!", type: .nearFC, instrument: nil
        ) { song, index in
            SuggestionSongItem(song: song, instrument: [Instrument.lead, .bass, .drums, .vocals][index % 4])
        },
        Template(
            key: "unplayed_drums", title: "New on Drums",
            description: "Songs you haven't played on Drums yet.", type: .unplayed, instrument: .drums
        ) { song, _ in
            SuggestionSongItem(song: song, instrument: .drums)
        },
    ]

    /// The infinite-scroll demo's six web `CATEGORY_TEMPLATES`, in its order.
    static let scrollTemplates: [Template] = [
        templates[0],
        templates[1],
        Template(
            key: "stale_vocals_1", title: "Play Tap Vocals This Season",
            description: "Songs you haven't played on Tap Vocals this season.", type: .stale, instrument: .vocals
        ) { song, _ in
            SuggestionSongItem(song: song, instrument: .vocals)
        },
        templates[2],
        templates[3],
        Template(
            key: "variety_pack", title: "Variety Pack",
            description: "Two different artists for variety.", type: .varietyPack, instrument: nil
        ) { song, _ in
            SuggestionSongItem(song: song)
        },
    ]
}

/// The Suggestions page's real category card (``SuggestionCategoryCardView``) over live
/// catalogue songs, or its layout with redacted placeholder songs while songs load or without a
/// session (hosted tests). Read-only.
private struct FirstRunSuggestionCard: View {
    let category: SuggestionCategory
    let session: FestivalSession?

    var body: some View {
        if let session {
            SuggestionCategoryCardView(category: category, session: session)
                .allowsHitTesting(false)
        } else {
            approximation(category)
        }
    }

    /// The card's layout while songs load or without a session (hosted tests), with
    /// redacted placeholder songs rather than invented titles.
    private func approximation(_ category: SuggestionCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(FestivalText.primary)
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
            }
            ForEach(Array(category.songs.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 12) {
                    InstrumentIcon(item.instrument ?? .lead, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.song.title).font(.subheadline.weight(.semibold))
                        Text(item.song.artist).font(.caption)
                    }
                    .foregroundStyle(FestivalText.primary)
                    .firstRunRedacted(item.song)
                    Spacer(minLength: 0)
                    if let trailing = item.percentileDisplay ?? item.percent.map({ "\(Int($0))%" }) {
                        Text(trailing)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandTokens.accentBlue)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .festivalCard(cornerRadius: 16)
    }
}

// MARK: - suggestions-global-filter

/// Ported from `pages/suggestions/firstRun/demo/GlobalFilterDemo.tsx`: the page's real
/// **Filter Suggestions** sheet (read-only) opened at its General section, every
/// suggestion type on.
struct FirstRunSuggestionsGlobalFilterDemo: View {
    var body: some View {
        SuggestionsFilterSheet(applied: SuggestionFilterSettings(), visibleInstruments: []) { _ in }
            .firstRunSheetPreview(height: 460)
    }
}

// MARK: - suggestions-instrument-filter

/// Ported from `pages/suggestions/firstRun/demo/InstrumentFilterDemo.tsx`: the real
/// **Filter Suggestions** sheet (read-only) at its per-instrument switches, as the page
/// lists them for the charts enabled in Settings.
struct FirstRunSuggestionsInstrumentFilterDemo: View {
    var body: some View {
        SuggestionsFilterSheet(
            applied: SuggestionFilterSettings(), visibleInstruments: [.lead, .bass, .drums, .vocals]
        ) { _ in }
            .firstRunSheetPreview(height: 460)
    }
}

// MARK: - suggestions-infinite-scroll

/// Ported from `pages/suggestions/firstRun/demo/InfiniteScrollDemo.tsx`: the web's six real
/// category cards over live catalogue songs, cascading in 125 ms apart, then gliding upward at
/// 30 pt/s from 100 ms and jumping back to the top at the end, under 36 pt edge fades on
/// whichever edges hide cards (web `fx.fadeTop/fadeBottom/fadeBoth`; ``FirstRunAutoScroll``).
///
/// The glide is a `TimelineView` that runs only while this slide is the one on screen in an
/// active scene (`firstRunDemoActive`); Reduce Motion (system or the app's) or the UI-test still
/// override hold the top of the stack. Reduce Transparency or Increase Contrast make the fades
/// hard edges (scroll-edge R7).
struct FirstRunSuggestionsInfiniteScrollDemo: View {
    @Environment(\.firstRunDemoActive) private var demoActive
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @ScrollEdgeHardEdge private var hardEdge
    @State private var trackHeight: CGFloat = 0
    @State private var startedAt = Date()

    private var running: Bool {
        demoActive && !(systemReduceMotion || appReduceMotion) && !DebugAnimationOverride.stillBackground
    }

    var body: some View {
        let templates = FirstRunSuggestionsCategoryCardDemo.scrollTemplates
        let perCard = FirstRunSuggestionsCategoryCardDemo.songsPerCard
        FirstRunCatalogueSongs(count: perCard * templates.count) { pool, session in
            GeometryReader { proxy in
                let maxOffset = Double(max(0, trackHeight - proxy.size.height))
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !running || maxOffset <= 0)) { context in
                    let offset = running
                        ? FirstRunAutoScroll.offset(
                            elapsed: context.date.timeIntervalSince(startedAt), maxOffset: maxOffset
                        )
                        : 0
                    track(pool: pool, session: session, templates: templates)
                        .offset(y: -offset)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .clipped()
                        .mask(fadeMask(FirstRunAutoScroll.edges(offset: offset, maxOffset: maxOffset)))
                }
            }
        }
        .onChange(of: running, initial: true) { _, now in
            if now { startedAt = Date() }
        }
        .accessibilityHidden(true)
    }

    private func track(
        pool: [Song], session: FestivalSession?, templates: [FirstRunSuggestionsCategoryCardDemo.Template]
    ) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(templates.enumerated()), id: \.offset) { index, template in
                let songs = FirstRunSuggestionsCategoryCardDemo.window(of: pool, template: index)
                FirstRunSuggestionCard(category: template.category(songs), session: session)
                    .firstRunStagger(index)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { trackHeight = $0 }
    }

    /// Opaque viewport with a linear ramp on each edge that hides cards.
    private func fadeMask(_ edges: FirstRunAutoScroll.Edges) -> some View {
        let ramp = CGFloat(ScrollEdgeFade.ramp(FirstRunAutoScroll.edgeFade, hardEdge: hardEdge))
        return VStack(spacing: 0) {
            LinearGradient(colors: [edges.top ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: ramp)
            Color.black
            LinearGradient(colors: [.black, edges.bottom ? .clear : .black], startPoint: .top, endPoint: .bottom)
                .frame(height: ramp)
        }
    }
}
