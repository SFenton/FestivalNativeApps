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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var template = 0
    @State private var fading: Set<Int> = []

    var body: some View {
        FirstRunCatalogueSongs(count: Self.songsPerCard * Self.templates.count) { pool, session in
            let songs = Self.window(of: pool, template: template)
            let category = Self.templates[template].category(songs)
            Group {
                if let session {
                    // The page's real category card (operator batch 7) over live catalogue songs.
                    SuggestionCategoryCardView(category: category, session: session)
                        .allowsHitTesting(false)
                } else {
                    approximation(category)
                }
            }
            .firstRunSwapRow(0, key: template, rise: 8)
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

/// Ported from `pages/suggestions/firstRun/demo/GlobalFilterDemo.tsx`: the suggestion-type
/// toggle list, all enabled.
struct FirstRunSuggestionsGlobalFilterDemo: View {
    private let types = ["Near Full Combo", "Percentile Push", "Unplayed Songs", "Stale Scores", "Variety Pack"]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(types, id: \.self) { type in
                toggleRow(type)
            }
        }
        .padding(14)
        .festivalCard(cornerRadius: 16)
        .accessibilityHidden(true)
    }

    private func toggleRow(_ label: String) -> some View {
        HStack {
            Text(label).foregroundStyle(FestivalText.primary).font(.subheadline)
            Spacer(minLength: 0)
            Capsule()
                .fill(BrandTokens.accentBlue)
                .frame(width: 40, height: 24)
                .overlay(Circle().fill(.white).frame(width: 20, height: 20).offset(x: 8))
        }
    }
}

// MARK: - suggestions-instrument-filter

/// Ported from `pages/suggestions/firstRun/demo/InstrumentFilterDemo.tsx`: the instrument
/// selector plus that instrument's own suggestion-type toggles.
struct FirstRunSuggestionsInstrumentFilterDemo: View {
    private let instruments: [Instrument] = [.lead, .bass, .drums, .vocals]
    private let types = ["Near Full Combo", "Percentile Push", "Unplayed Songs"]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(instruments, id: \.self) { instrument in
                    InstrumentIcon(instrument, size: 30)
                        .padding(6)
                        .background(
                            instrument == .lead ? BrandTokens.accentBlue.opacity(0.3) : .clear,
                            in: Circle()
                        )
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(types, id: \.self) { type in
                    HStack {
                        Text(type).foregroundStyle(FestivalText.primary).font(.subheadline)
                        Spacer(minLength: 0)
                        Capsule()
                            .fill(BrandTokens.accentBlue)
                            .frame(width: 36, height: 22)
                            .overlay(Circle().fill(.white).frame(width: 18, height: 18).offset(x: 7))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .festivalCard(cornerRadius: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - suggestions-infinite-scroll

/// Ported from `pages/suggestions/firstRun/demo/InfiniteScrollDemo.tsx`: a stack of suggestion
/// cards with a bottom fade hinting more content below. The web auto-scrolls the stack on a
/// `requestAnimationFrame` loop; this static port shows the resting view — a perpetual scroll
/// loop is exactly the "heavy" always-running animation the carousel rule excludes.
struct FirstRunSuggestionsInfiniteScrollDemo: View {
    private let cards: [(String, Instrument)] = [
        ("Near Full Combo", .lead), ("Percentile Push", .bass), ("Unplayed Songs", .drums),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(cards, id: \.0) { title, instrument in
                HStack(spacing: 10) {
                    InstrumentIcon(instrument, size: 22)
                    Text(title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(FestivalText.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .festivalCard(cornerRadius: 12)
            }
        }
        .mask(
            LinearGradient(
                stops: [.init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .accessibilityHidden(true)
    }
}
