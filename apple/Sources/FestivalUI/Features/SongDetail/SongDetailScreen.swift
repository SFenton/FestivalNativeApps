import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Song detail

/// Catalog detail retains source section order for currently available data.
struct SongDetailScreen: View {
    let song: Song
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @AppStorage("fst.settings.pathDefaultView") private var pathDefaultView = PathDisplayMode.image
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting")
    private var disableShopHighlighting = false
    @State private var pathsPresented = false
    @State private var shopRefreshFailure: String?
    @State private var quickLinks = QuickLinksController()

    private struct ShopDetailTaskKey: Equatable {
        let publicationRevision: Int
        let hidden: Bool
    }

    private var charted: [Instrument] {
        Instrument.allCases.filter(song.supports)
    }

    private var pathInstruments: [Instrument] {
        Instrument.allCases.filter {
            $0 != .karaoke && visibleInstruments.contains($0)
        }
    }

    private var shopOffer: ShopSong? {
        hideShop ? nil : session.shopOffersById[song.songId]
    }

    private var shopHighlight: ShopHighlight? {
        ShopPresentationPolicy.highlight(
            for: shopOffer, hidden: hideShop,
            highlightingDisabled: disableShopHighlighting
        )
    }

    /// Intensity, then one entry per visible leaderboard card, in source order
    /// (`.agents/controls/quick-links/ios.md`; band/score-history sections are
    /// not built yet).
    private var quickLinkSections: [QuickLinkSection] {
        [QuickLinkSection(id: "intensity", title: "Intensity", icon: .system("chart.bar.fill"))]
            + charted.filter(visibleInstruments.contains).map { instrument in
                QuickLinkSection(
                    id: "instrument-\(instrument.rawValue)", title: instrument.label,
                    icon: .instrument(instrument)
                )
            }
    }

    /// Supply enabled chart links without hiding the PWA's full Intensity grid.
    ///
    /// - Parameters:
    ///   - song: Catalog record opened from the Songs route.
    ///   - session: Process-lifetime client and artwork state.
    ///   - visibleInstruments: Solo charts enabled in Settings.
    init(
        song: Song, session: FestivalSession,
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases)
    ) {
        self.song = song
        self.session = session
        self.visibleInstruments = visibleInstruments
    }

    var body: some View {
        #if os(iOS)
        detailContent.navigationBarTitleDisplayMode(.inline)
        #else
        detailContent
        #endif
    }

    /// Branded detail beneath platform-owned compact back navigation.
    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    ArtworkTile(raw: song.albumArt, session: session, size: 96)
                        .id(song.albumArt)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        MarqueeText(song.title, font: .title.bold())
                        MarqueeText(song.artist, font: .body)
                            .foregroundStyle(BrandTokens.textSecondary)
                        if let year = song.year {
                            Text(year.formatted(.number.grouping(.never)))
                                .foregroundStyle(BrandTokens.textSecondary)
                        }
                        if let shopHighlight {
                            Label(
                                "Item Shop: \(shopHighlight.label)",
                                systemImage: shopHighlight == .leavingTomorrow
                                    ? "clock" : "sparkles"
                            )
                            .font(.caption.bold())
                            .foregroundStyle(
                                shopHighlight == .leavingTomorrow
                                    ? BrandTokens.textPrimary : BrandTokens.gold
                            )
                            .padding(8)
                            .background(
                                shopHighlight == .leavingTomorrow
                                    ? BrandTokens.statusRed : BrandTokens.cardBackground,
                                in: Capsule()
                            )
                            .accessibilityIdentifier("fst.song-detail.shop-badge")
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if !hideShop, let error = session.shopError
                    ?? (session.currentShop == nil ? shopRefreshFailure : nil) {
                    FreshnessDisclosure(
                        message: "Item Shop status unavailable: \(error)",
                        symbol: "exclamationmark.triangle"
                    )
                    .accessibilityIdentifier("fst.song-detail.shop-error")
                }

                VStack(alignment: .leading, spacing: 12) {
                    FestivalSectionHeader("Intensity")
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10
                    ) {
                        ForEach(charted) { instrument in
                            if let level = song.difficulty?.chartedValue(for: instrument) {
                                HStack(spacing: 8) {
                                    InstrumentIcon(
                                        instrument, keyboard: song.usesKeyboardIcon
                                            && (instrument == .lead || instrument == .proLead),
                                        size: 22
                                    )
                                    DifficultyMeter(level: level, raw: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .festivalGlass(.card, cornerRadius: 16)
                }
                .accessibilityIdentifier("fst.song-detail.intensity")
                .quickLinkSection(id: "intensity", title: "Intensity", symbol: "chart.bar.fill")

                VStack(alignment: .leading, spacing: 12) {
                    FestivalSectionHeader("Leaderboards")
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 360), spacing: 12)],
                        alignment: .leading, spacing: 16
                    ) {
                        ForEach(charted.filter(visibleInstruments.contains)) { instrument in
                            SongScorePreview(
                                song: song, instrument: instrument, session: session
                            )
                            .quickLinkSection(QuickLinkSection(
                                id: "instrument-\(instrument.rawValue)", title: instrument.label,
                                icon: .instrument(instrument)
                            ))
                        }
                    }
                }
            }
            .padding(16)
        }
        .quickLinks(quickLinks, title: "Quick Links", sections: quickLinkSections)
        .festivalBackground(.song(song.albumArt), session: session)
        .navigationTitle("")
        .toolbar {
            if let offer = shopOffer {
                ToolbarItem(placement: .primaryAction) {
                    Link(destination: offer.shopUrl) {
                        Label("Item Shop", systemImage: "bag")
                    }
                    .accessibilityIdentifier("fst.song-detail.shop")
                }
            }
            if !pathInstruments.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        pathsPresented = true
                    } label: {
                        Label("Paths", systemImage: "map")
                    }
                    .accessibilityIdentifier("fst.song-detail.paths")
                }
            }
            QuickLinksToolbarItem(quickLinks)
        }
        .sheet(isPresented: $pathsPresented) {
            if let first = pathInstruments.first {
                SongPathsSheet(
                    song: song, session: session, instruments: pathInstruments,
                    firstInstrument: first, defaultDisplay: pathDefaultView,
                    warnAboutKaraoke: visibleInstruments.contains(.karaoke)
                )
            }
        }
        .task(id: ShopDetailTaskKey(
            publicationRevision: session.publicationRevision, hidden: hideShop
        )) {
            guard !hideShop, session.currentShop == nil,
                  session.shopError == nil else { return }
            do {
                _ = try await session.shop()
                try Task.checkCancellation()
                shopRefreshFailure = nil
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                shopRefreshFailure = error.localizedDescription
            }
        }
    }
}

/// Load a visible chart's top ten via the same public, publication-aware API as Solo.
