import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Session plumbing

extension EnvironmentValues {
    /// The app session a first-run carousel was opened from, so song demos can show real
    /// catalogue songs and their artwork. Nil in hosted tests and previews, where demos show
    /// redacted ``FirstRunDemoSongs/placeholders(count:)``.
    @Entry var firstRunSession: FestivalSession?
}

/// Supplies real catalogue songs to a first-run demo, as the web's `useDemoSongs` /
/// `useItemShopDemoSongs` do (selection rules: ``FirstRunDemoSongs/pick(from:count:preferring:)``).
///
/// Until the catalogue answers, or when it can't, the content receives redacted placeholders
/// and a nil session so no real-row view is driven by a stand-in; demos never invent titles.
/// The catalogue read is the app's cached, keyless `/api/songs`; the Item Shop source only
/// reuses an already-loaded Shop feed from the same observed publication and never fetches one.
///
/// With `rotates`, the rows rotate through a larger pool on the web's `useDemoSongs` cycle
/// (``FirstRunRowRotation``): every 5 s one row (two for 4-6 rows) fades out for 400 ms, takes
/// a song not already shown and fades back in, while the slide is visible. Content marks each
/// row with ``SwiftUI/View/firstRunSwapRow(_:key:rise:)`` and positional `ForEach` identity.
struct FirstRunCatalogueSongs<Content: View>: View {
    /// Where preferred songs come from.
    enum Source {
        /// Catalogue songs with artwork, Epic Games songs first.
        case catalogue
        /// Current Item Shop songs first, then `catalogue` songs.
        case itemShop
    }

    /// Songs a rotating demo cycles through; bounded so artwork stays within the shared caches.
    static var rotationPoolSize: Int { 24 }

    @Environment(\.firstRunSession) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var live: FirstRunRowRotation<Song>?
    @State private var fading: Set<Int> = []
    @State private var swapTick = 0
    private let count: Int
    private let source: Source
    private let rotates: Bool
    private let swapsWhole: Bool
    private let content: ([Song], FestivalSession?) -> Content

    /// - Parameters:
    ///   - count: Maximum rows the demo shows.
    ///   - source: Song preference order.
    ///   - rotates: Rotate rows through a pool of songs on the web demos' swap cycle.
    ///   - swapsWhole: Fade the whole demo (slot 0) for each swap instead of only the
    ///     swapped rows, as the web's Rivals detail demo does.
    ///   - content: Builds the demo from songs (placeholders while not live) and the session
    ///     (nil while not live).
    init(
        count: Int = 3, source: Source = .catalogue, rotates: Bool = false, swapsWhole: Bool = false,
        @ViewBuilder content: @escaping ([Song], FestivalSession?) -> Content
    ) {
        self.count = count
        self.source = source
        self.rotates = rotates
        self.swapsWhole = swapsWhole
        self.content = content
    }

    var body: some View {
        content(live?.rows ?? FirstRunDemoSongs.placeholders(count: count), live == nil ? nil : session)
            .environment(\.firstRunFadingRows, fading)
            .environment(\.firstRunSwapTick, swapTick)
            .task { await load() }
            .firstRunDemoTicker(enabled: rotates && live?.canRotate == true, usesArtwork: true) {
                await swap()
            }
    }

    private func load() async {
        guard live == nil, let session, let payload = try? await session.catalog() else { return }
        var preferred: [String] = []
        if source == .itemShop, let shop = session.currentShop,
           shop.observedPublicationId == payload.observedPublicationId {
            preferred = shop.sortedSongs.map(\.songId)
        }
        let poolSize = rotates ? max(count, Self.rotationPoolSize) : count
        let picked = FirstRunDemoSongs.pick(from: payload.catalog.songs, count: poolSize, preferring: preferred)
        guard !picked.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            live = FirstRunRowRotation(pool: picked, visible: count)
        }
    }

    private func swap() async {
        guard var next = live else { return }
        let indices = next.nextSwap()
        guard !indices.isEmpty else { return }
        live = next
        prefetchArtwork(after: next, replacing: indices)
        await FirstRunDemoSwap.run(
            reduceMotion: reduceMotion,
            fadeOut: { fading = swapsWhole ? [0] : Set(indices) },
            update: {
                live?.replace(indices)
                swapTick += 1
            },
            fadeIn: { fading = [] }
        )
    }

    /// Warm the shared artwork cache for the songs about to swap in while the old rows fade
    /// out, so new rows rarely show a loading tile.
    private func prefetchArtwork(after rotation: FirstRunRowRotation<Song>, replacing indices: [Int]) {
        guard let session else { return }
        var preview = rotation
        preview.replace(indices)
        for index in indices where preview.rows.indices.contains(index) {
            guard let raw = preview.rows[index].albumArt, !raw.isEmpty else { continue }
            Task { _ = try? await session.preparedArtwork(raw: raw, maxPixels: 132) }
        }
    }
}

/// A read-only preview of real app UI: no hit testing and hidden from VoiceOver (the slide's
/// combined title/description is its accessible content). An embedded sheet shows only its
/// content, so it never adds its title and Close to the guide's own bar (issue #25).
private struct FirstRunInertPreview: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.festivalModalPreview, true)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Shows real app UI read-only (``FirstRunInertPreview``).
    func firstRunInert() -> some View { modifier(FirstRunInertPreview()) }

    /// Shows the top `height` points of a real sheet read-only, framed as a sheet card, as the
    /// Songs Sort and Filter demos do.
    func firstRunSheetPreview(height: CGFloat) -> some View {
        frame(height: height, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BrandTokens.glassBorder, lineWidth: 1)
            )
            .firstRunInert()
    }
}

/// A demo row built from the real Songs row pieces when no session exists to drive
/// `SongRowView` itself (hosted tests).
private struct FirstRunRowChrome<Detail: View, Trailing: View>: View {
    let song: Song
    let session: FestivalSession?
    var outline: Color?
    /// Content under the title, where `SongRowView` puts status chips.
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            FirstRunSongArt(song: song, session: session)
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    MarqueeText(song.title, font: .headline)
                    MarqueeText(subtitle, font: .subheadline)
                }
                .foregroundStyle(FestivalText.primary)
                .firstRunRedacted(song)
                detail()
            }
            .marqueeSync()
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .festivalCard(cornerRadius: 12)
        .overlay {
            if let outline {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(outline, lineWidth: 2)
            }
        }
    }

    private var subtitle: String {
        [song.artist, song.year.map(String.init), song.formattedDuration]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// The real `SongRowView` when a session exists, otherwise the same layout from its parts.
/// Songs and the Item Shop demos share it, so a highlighted row pulses with the row's own
/// ``ShopRowPulseBorder`` (green in the shop, gold when new, red when leaving tomorrow).
struct FirstRunSongRow: View {
    let song: Song
    let session: FestivalSession?
    var highlight: ShopHighlight?
    /// In the Item Shop with highlighting on (green pulse and bag, web `shopHighlight`).
    var inShop = false

    var body: some View {
        if let session {
            SongRowView(
                song: song, instrument: nil, session: session, highContrast: false,
                shopHighlight: highlight, inShop: inShop
            )
        } else {
            FirstRunRowChrome(
                song: song, session: nil,
                outline: inShop || highlight != nil ? ShopStatusTone(highlight: highlight).borderColor : nil,
                detail: { EmptyView() }, trailing: { EmptyView() }
            )
        }
    }
}

// MARK: - songs-song-list

/// `SongRowDemo.tsx`, with the app's real Songs rows over live catalogue songs.
struct FirstRunNativeSongListDemo: View {
    var body: some View {
        FirstRunCatalogueSongs(rotates: true) { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    FirstRunSongRow(song: song, session: session)
                        .firstRunSwapRow(index, key: song.id)
                }
            }
        }
        .firstRunInert()
    }
}

// MARK: - songs-sort

/// `SortDemo.tsx`, as the real Songs **Sort** sheet (read-only, top of the sheet).
struct FirstRunNativeSortDemo: View {
    var body: some View {
        SongsSortSheet(mode: .title, ascending: true, showShop: true, shopAvailable: true) { _, _ in }
            .firstRunSheetPreview(height: 420)
    }
}

// MARK: - songs-filter

/// `FilterDemo.tsx`, as the real Songs **Filter** sheet (read-only, top of the sheet).
struct FirstRunNativeFilterDemo: View {
    var body: some View {
        SongsFilterSheet(
            appliedGeneral: SongGeneralFilter(shop: .availableOnly),
            showShop: true, shopAvailable: true,
            availableDecades: [1970, 1980, 1990, 2000, 2010, 2020],
            appliedInstrument: .lead, selectedPlayer: true, scoreAvailable: true
        ) { _, _, _ in }
            .firstRunSheetPreview(height: 460)
    }
}

// MARK: - songs-navigation

/// `NavigationDemo.tsx`, as a real system tab bar (Liquid Glass on iOS 26) with the app's
/// phone tabs.
struct FirstRunNativeNavigationDemo: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, section in
                Color.clear
                    .tabItem { Label(section.title, systemImage: section.symbol) }
                    .tag(index)
            }
        }
        // The carousel's `.page` style is inherited by nested tab views, which would turn
        // this one into an empty pager with no tab bar (issue #380).
        .tabViewStyle(.automatic)
        .frame(height: 150)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .firstRunInert()
    }

    /// The shell's own tab titles and symbols (``FestivalSection``).
    private static let tabs: [FestivalSection] = [.songs, .suggestions, .compete, .statistics, .settings]
}

// MARK: - songs-icons

/// `SongIconsDemo.tsx`: real Songs rows with the app's instrument status chips (full combo,
/// scored, no score). Rows rotate like the web's, and each song's chips follow the web's
/// per-title pattern (``SongInstrumentBadge/demoPattern(title:instruments:)``).
struct FirstRunNativeIconsDemo: View {
    var body: some View {
        FirstRunCatalogueSongs(count: 2, rotates: true) { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    FirstRunRowChrome(song: song, session: session) {
                        SongInstrumentStatusChips(
                            songId: song.songId,
                            badges: SongInstrumentBadge.demoPattern(title: song.title, instruments: Self.instruments),
                            keyboard: song.usesKeyboardIcon
                        )
                    } trailing: { EmptyView() }
                    .firstRunSwapRow(index, key: song.id)
                }
            }
        }
        .firstRunInert()
    }

    private static let instruments: [Instrument] = [.lead, .bass, .drums, .vocals]
}

// MARK: - songs-metadata

/// `MetadataDemo.tsx`: a real Songs score card with the app's metadata field and pills. The
/// song rotates like the web's, and each song shows one of the web's `META_DATA` score
/// records, picked by its title so a new song brings new values.
struct FirstRunNativeMetadataDemo: View {
    var body: some View {
        FirstRunCatalogueSongs(count: 1, rotates: true) { songs, session in
            if let song = songs.first {
                let meta = Self.meta(for: song)
                FirstRunRowChrome(song: song, session: session) {
                    SongProfileMetadataPills(fields: meta.pills, songId: song.songId)
                } trailing: {
                    SongMetadataFieldView(field: .score(meta.score), songId: song.songId)
                }
                .firstRunSwapRow(0, key: song.id)
            }
        }
        .firstRunInert()
    }

    /// One of the web demo's `META_DATA` records.
    struct Meta {
        let score: Int
        /// Service units: ten-thousandths of a percent (1,000,000 = 100 %).
        let accuracy: Double
        let fullCombo: Bool
        let stars: Int
        let percentile: String
        let season: Int
        let difficulty: Int

        @MainActor var pills: [SongMetadataField] {
            [
                .accuracy(accuracy, fullCombo: fullCombo, percentageVisible: true,
                          tint: try? ScoreFormatting.accuracyTint(accuracy)),
                .stars(count: min(stars, 5), gold: stars >= 6),
                .percentile(percentile, tier: SuggestionSongRowView.tier(percentile)),
                .season(season, current: false),
                .difficulty(difficulty),
            ]
        }
    }

    /// The web's `META_DATA`.
    static let records: [Meta] = [
        .init(score: 198_942, accuracy: 1_000_000, fullCombo: true, stars: 6, percentile: "Top 1%", season: 12, difficulty: 4),
        .init(score: 157_320, accuracy: 980_000, fullCombo: false, stars: 5, percentile: "Top 5%", season: 10, difficulty: 3),
        .init(score: 142_800, accuracy: 960_000, fullCombo: false, stars: 5, percentile: "Top 8%", season: 11, difficulty: 5),
        .init(score: 185_600, accuracy: 1_000_000, fullCombo: true, stars: 6, percentile: "Top 2%", season: 9, difficulty: 2),
        .init(score: 123_400, accuracy: 940_000, fullCombo: false, stars: 4, percentile: "Top 15%", season: 8, difficulty: 4),
        .init(score: 176_100, accuracy: 1_000_000, fullCombo: true, stars: 6, percentile: "Top 3%", season: 12, difficulty: 3),
        .init(score: 110_250, accuracy: 910_000, fullCombo: false, stars: 4, percentile: "Top 20%", season: 7, difficulty: 5),
        .init(score: 168_900, accuracy: 970_000, fullCombo: false, stars: 5, percentile: "Top 6%", season: 11, difficulty: 2),
        .init(score: 191_200, accuracy: 1_000_000, fullCombo: true, stars: 6, percentile: "Top 1%", season: 10, difficulty: 4),
        .init(score: 135_700, accuracy: 950_000, fullCombo: false, stars: 5, percentile: "Top 10%", season: 9, difficulty: 3),
    ]

    /// The record a song shows, chosen by its title's web hash.
    static func meta(for song: Song) -> Meta {
        records[Int(Int64(FirstRunDemoScorePattern.hash(song.title)).magnitude % UInt64(records.count))]
    }
}

// MARK: - Item Shop rows

/// `ShopHighlightDemo.tsx` / `NewInShopDemo.tsx` / `LeavingTomorrowDemo.tsx`, as the real
/// Songs rows with their Item Shop outline and badge.
struct FirstRunNativeShopDemo: View {
    enum Kind { case highlight, new, leaving }
    let kind: Kind

    var body: some View {
        FirstRunCatalogueSongs { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    FirstRunSongRow(song: song, session: session, highlight: highlight(index))
                }
            }
        }
        .firstRunInert()
    }

    private func highlight(_ index: Int) -> ShopHighlight? {
        switch kind {
        case .highlight: [ShopHighlight.new, .leavingTomorrow, nil][index % 3]
        case .new: index == 0 ? .new : nil
        case .leaving: index == 0 ? .leavingTomorrow : nil
        }
    }
}
