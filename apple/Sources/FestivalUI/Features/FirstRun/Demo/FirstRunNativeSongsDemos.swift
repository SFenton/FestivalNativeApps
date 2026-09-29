import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Session plumbing

extension EnvironmentValues {
    /// The app session a first-run carousel was opened from, so Songs demos can show the
    /// real Songs rows (live catalogue songs and their artwork). Nil in hosted tests and
    /// previews, where demos fall back to ``Song/firstRunFallback``.
    @Entry var firstRunSession: FestivalSession?
}

/// Supplies up to three real catalogue songs (the web demos switch to catalogue songs once
/// loaded), falling back to offline stand-ins. The catalogue read is the app's cached,
/// keyless `/api/songs`; nothing new is requested when Songs already loaded it.
struct FirstRunCatalogueSongs<Content: View>: View {
    @Environment(\.firstRunSession) private var session
    @State private var songs = Song.firstRunFallback
    @ViewBuilder let content: ([Song], FestivalSession?) -> Content

    var body: some View {
        content(songs, session)
            .task {
                guard let session,
                      let payload = try? await session.catalog() else { return }
                let live = payload.catalog.songs.filter { $0.albumArt != nil }.prefix(3)
                if live.count == 3 { songs = Array(live) }
            }
    }
}

/// A read-only preview of real app UI: no hit testing and hidden from VoiceOver (the slide's
/// combined title/description is its accessible content).
private struct FirstRunInertPreview: ViewModifier {
    func body(content: Content) -> some View {
        content
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension View {
    func firstRunInert() -> some View { modifier(FirstRunInertPreview()) }
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
            if let session {
                ArtworkTile(raw: song.albumArt, session: session, size: 44)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrandTokens.surfaceMuted)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(song.title, font: .headline)
                    .foregroundStyle(FestivalText.primary)
                MarqueeText(subtitle, font: .subheadline)
                    .foregroundStyle(FestivalText.primary)
                detail()
            }
            .marqueeSync()
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .festivalGlass(.card, cornerRadius: 12)
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
private struct FirstRunSongRow: View {
    let song: Song
    let session: FestivalSession?
    var highlight: ShopHighlight?

    var body: some View {
        if let session {
            SongRowView(
                song: song, instrument: nil, session: session, highContrast: false,
                shopHighlight: highlight
            )
        } else {
            FirstRunRowChrome(
                song: song, session: nil,
                outline: highlight == .leavingTomorrow ? BrandTokens.statusRed
                    : highlight == .new ? BrandTokens.gold : nil,
                detail: { EmptyView() }, trailing: { EmptyView() }
            )
        }
    }
}

// MARK: - songs-song-list

/// `SongRowDemo.tsx`, with the app's real Songs rows over live catalogue songs.
struct FirstRunNativeSongListDemo: View {
    var body: some View {
        FirstRunCatalogueSongs { songs, session in
            VStack(spacing: 8) {
                ForEach(songs) { FirstRunSongRow(song: $0, session: session) }
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
            .frame(height: 420, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BrandTokens.glassBorder, lineWidth: 1)
            )
            .firstRunInert()
    }
}

// MARK: - songs-filter

/// `FilterDemo.tsx`, as the real Songs **Filter** sheet (read-only, top of the sheet).
struct FirstRunNativeFilterDemo: View {
    var body: some View {
        SongsFilterSheet(
            applied: SongShopFilter(inShop: true, leavingTomorrow: false),
            showShop: true, shopAvailable: true, profileAvailable: true,
            appliedInstrument: .lead, selectedPlayer: true, scoreAvailable: true
        ) { _, _, _ in }
            .frame(height: 460, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BrandTokens.glassBorder, lineWidth: 1)
            )
            .firstRunInert()
    }
}

// MARK: - songs-navigation

/// `NavigationDemo.tsx`, as a real system tab bar (Liquid Glass on iOS 26) with the app's
/// phone tabs.
struct FirstRunNativeNavigationDemo: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, tab in
                Color.clear
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(index)
            }
        }
        .frame(height: 150)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .firstRunInert()
    }

    private static let tabs: [(title: String, symbol: String)] = [
        ("Songs", "music.note.list"), ("Suggestions", "sparkles"),
        ("Compete", "trophy.fill"), ("Statistics", "chart.bar.fill"),
        ("Settings", "gearshape.fill"),
    ]
}

// MARK: - songs-icons

/// `SongIconsDemo.tsx`: a real Songs row with the app's instrument status chips (full combo,
/// scored, no score, not charted).
struct FirstRunNativeIconsDemo: View {
    var body: some View {
        FirstRunCatalogueSongs { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.prefix(2).enumerated()), id: \.element.id) { index, song in
                    FirstRunRowChrome(song: song, session: session) {
                        SongInstrumentStatusChips(
                            songId: song.songId,
                            badges: index == 0 ? Self.firstRow : Self.secondRow,
                            keyboard: song.usesKeyboardIcon
                        )
                    } trailing: { EmptyView() }
                }
            }
        }
        .firstRunInert()
    }

    private static let firstRow: [SongInstrumentBadge] = [
        .demo(.lead, .fullCombo), .demo(.bass, .scored), .demo(.drums, .noScore),
        .demo(.vocals, .scored),
    ]
    private static let secondRow: [SongInstrumentBadge] = [
        .demo(.lead, .scored), .demo(.bass, .unavailable), .demo(.drums, .fullCombo),
        .demo(.vocals, .noScore),
    ]
}

// MARK: - songs-metadata

/// `MetadataDemo.tsx`: a real Songs score card with the app's metadata field and pills.
struct FirstRunNativeMetadataDemo: View {
    var body: some View {
        FirstRunCatalogueSongs { songs, session in
            if let song = songs.first {
                FirstRunRowChrome(song: song, session: session) {
                    SongProfileMetadataPills(fields: Self.pills, songId: song.songId)
                } trailing: {
                    SongMetadataFieldView(field: .score(248_192), songId: song.songId)
                }
            }
        }
        .firstRunInert()
    }

    private static let pills: [SongMetadataField] = [
        // Service accuracy is in ten-thousandths of a percent: 984,000 = 98.4 %.
        .accuracy(984_000, fullCombo: false, percentageVisible: true,
                  tint: try? ScoreFormatting.accuracyTint(984_000)),
        .percentile("Top 3%", tier: .topFive),
        .stars(count: 5, gold: false),
        .season(5, current: false),
    ]
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
