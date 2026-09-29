import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Song detail

/// Catalog detail retains source section order for currently available data.
///
/// Like the web `SongDetailPage`, only a spinner shows until every visible chart's top
/// ten and (with a selected player) the song's score history have loaded; then the
/// page fades in and its sections stagger (operator batch 6.41). The selected player's
/// score history is a section of this page (batch 6.39), after Intensity.
struct SongDetailScreen: View {
    let song: Song
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    /// Deep link to `/songs/:id/:instrument/history`: open scrolled to Score History on
    /// this instrument, every score listed.
    let historyFocus: Instrument?
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.leeway") private var leeway = 1.0
    /// Every card's first read (and the history) finished: the page may appear.
    @State private var ready = false
    @State private var previewPreloads: [Instrument: SongScorePreview.LoadState] = [:]
    @State private var historyEntries: [ScoreHistoryEntry] = []
    @State private var historyInstrument: Instrument?
    @State private var historyExpanded = false
    @State private var loadedGate: GateKey?
    @AppStorage("fst.settings.pathDefaultView") private var pathDefaultView = PathDisplayMode.image
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting")
    private var disableShopHighlighting = false
    @State private var pathsPresented = false
    @State private var shopRefreshFailure: String?
    @State private var quickLinks = QuickLinksController()
    /// Whether the hero title has scrolled under the navigation bar (gap #6). Only
    /// the Bool changes while scrolling, so the page body is not re-evaluated every frame.
    @State private var heroTitleHidden = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the page's first-appearance reads depend on.
    private struct GateKey: Hashable {
        let publicationRevision: Int
        let accountId: String?
        let leeway: Double?
    }

    private var gateKey: GateKey {
        GateKey(
            publicationRevision: session.publicationRevision,
            accountId: session.selectedPlayer?.accountId,
            leeway: filterInvalidScores ? (leeway * 10).rounded() / 10 : nil
        )
    }

    private var previewInstruments: [Instrument] { charted.filter(visibleInstruments.contains) }

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

    /// Breathing status colour for the Shop action (green / gold / red), or nil.
    private var shopTone: ShopStatusTone? {
        ShopStatusTone.tone(
            for: shopOffer, hidden: hideShop, highlightingDisabled: disableShopHighlighting
        )
    }

    /// Intensity, then one entry per visible leaderboard card, in source order
    /// (`.agents/controls/quick-links/ios.md`; band/score-history sections are
    /// not built yet).
    private var quickLinkSections: [QuickLinkSection] {
        [QuickLinkSection(id: "intensity", title: "Intensity", icon: .system("chart.bar.fill"))]
            + (historyEntries.isEmpty ? [] : [
                QuickLinkSection(id: "score-history", title: "Score History", icon: .system("chart.line.uptrend.xyaxis")),
            ])
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
    ///   - historyFocus: Open scrolled to Score History on this instrument (deep link).
    init(
        song: Song, session: FestivalSession,
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
        historyFocus: Instrument? = nil
    ) {
        self.song = song
        self.session = session
        self.visibleInstruments = visibleInstruments
        self.historyFocus = historyFocus
        _historyInstrument = State(initialValue: historyFocus)
        _historyExpanded = State(initialValue: historyFocus != nil)
    }

    var body: some View {
        #if os(iOS)
        detailContent.navigationBarTitleDisplayMode(.inline)
        #else
        detailContent
        #endif
    }

    /// Branded detail beneath platform-owned compact back navigation: a spinner until
    /// the page's reads settle, then the content.
    private var detailContent: some View {
        Group {
            if ready {
                loadedScroll
            } else {
                FestivalLoadingView(accessibilityLabel: "Loading \(song.title)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("fst.song-detail.loading")
            }
        }
        .quickLinks(quickLinks, title: "Quick Links", sections: quickLinkSections)
        .detailFadeTestSafe()
        .festivalBackground(.song(song.albumArt), session: session)
        .navigationTitle(song.title)
        .toolbar { detailToolbar }
        .sheet(isPresented: $pathsPresented) {
            if let first = pathInstruments.first {
                SongPathsSheet(
                    song: song, session: session, instruments: pathInstruments,
                    firstInstrument: first, defaultDisplay: pathDefaultView,
                    warnAboutKaraoke: visibleInstruments.contains(.karaoke)
                )
            }
        }
        .task(id: gateKey) { await loadGate() }
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

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .principal) {
            pinnedTitle
        }
        #endif
        if let offer = shopOffer {
            ToolbarItem(placement: .primaryAction) {
                shopAction(offer)
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

    /// The loaded page: header, Intensity, Score History, then the chart cards, fading
    /// in with the web's stagger.
    private var loadedScroll: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    ArtworkTile(raw: song.albumArt, session: session, size: 96)
                        .id(song.albumArt)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        MarqueeText(song.title, font: .title.bold())
                            .onGeometryChange(for: Bool.self) { proxy in
                                SongDetailPinnedTitlePolicy.isHeroHidden(
                                    titleMaxY: proxy.frame(in: .scrollView).maxY
                                )
                            } action: { hidden in
                                heroTitleHidden = hidden
                            }
                        MarqueeText(song.artist, font: .body)
                            .foregroundStyle(FestivalText.primary)
                        if let year = song.year {
                            Text(year.formatted(.number.grouping(.never)))
                                .foregroundStyle(FestivalText.primary)
                        }
                    }
                    .marqueeSync()
                }
                .accessibilityElement(children: .combine)
                .festivalFadeIn(isLoaded: true, index: 0)

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
                .festivalFadeIn(isLoaded: true, index: 1)

                if session.selectedPlayer != nil, !historyEntries.isEmpty {
                    SongScoreHistorySection(
                        entries: historyEntries, pool: previewInstruments,
                        keyboardIcon: song.usesKeyboardIcon,
                        instrument: $historyInstrument, expanded: $historyExpanded
                    )
                    .id(SongScoreHistorySection.anchor)
                    .quickLinkSection(
                        id: "score-history", title: "Score History", symbol: "chart.line.uptrend.xyaxis"
                    )
                    .festivalFadeIn(isLoaded: true, index: 2)
                }

                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 360), spacing: 12)],
                        alignment: .leading, spacing: 20
                    ) {
                        ForEach(Array(previewInstruments.enumerated()), id: \.element) { index, instrument in
                            SongScorePreview(
                                song: song, instrument: instrument, session: session,
                                preloaded: previewPreloads[instrument]
                            )
                            .quickLinkSection(QuickLinkSection(
                                id: "instrument-\(instrument.rawValue)", title: instrument.label,
                                icon: .instrument(instrument)
                            ))
                            .festivalFadeIn(isLoaded: true, index: index + 3)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            // Deep link (`/history`): land on the Score History section.
            guard historyFocus != nil, !historyEntries.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                proxy.scrollTo(SongScoreHistorySection.anchor, anchor: .top)
            }
        }
        }
    }

    // MARK: Load

    /// First appearance: read every visible chart's top ten and the selected player's
    /// history for this song in parallel, then show the page. Later key changes (new
    /// publication, leeway, profile) refresh the history quietly; the cards reload
    /// themselves.
    private func loadGate() async {
        let key = gateKey
        guard loadedGate != key else { return }
        if ready {
            await loadHistory()
            if !Task.isCancelled { loadedGate = key }
            return
        }
        async let history: Void = loadHistory()
        let previews = await SongDetailPreloader.previews(
            session: session, song: song, instruments: previewInstruments, leeway: key.leeway
        )
        await history
        guard !Task.isCancelled else { return }
        previewPreloads = previews
        loadedGate = key
        ready = true
    }

    /// Read the selected player's history for this song (every instrument). Anything
    /// but available rows hides the section, like the web.
    private func loadHistory() async {
        guard let accountId = session.selectedPlayer?.accountId else {
            historyEntries = []
            return
        }
        do {
            let payload = try await session.songHistory(accountId: accountId, songId: song.songId)
            try Task.checkCancellation()
            historyEntries = payload.state == .available
                ? payload.response.history.filter { $0.songId == song.songId } : []
        } catch {
            guard !Task.isCancelled else { return }
            historyEntries = []
        }
    }
}

// MARK: - Pinned identity and Shop action

extension SongDetailScreen {
    /// Official Item Shop action. While Shop highlighting is on, its circle breathes
    /// in the song's Shop status colour like the web's `shopBreathe*` button.
    ///
    /// - Parameter offer: Validated Shop row for this song.
    /// - Returns: Toolbar link with a spoken status.
    @ViewBuilder
    private func shopAction(_ offer: ShopSong) -> some View {
        if let tone = shopTone {
            Link(destination: offer.shopUrl) {
                Image(systemName: "bag")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .frame(width: 34, height: 34)
                    .modifier(ShopStatusBreathe(tone: tone))
            }
            .accessibilityLabel("Item Shop, \(tone.spokenStatus)")
            .accessibilityIdentifier("fst.song-detail.shop")
        } else {
            Link(destination: offer.shopUrl) {
                Label("Item Shop", systemImage: "bag")
            }
            .accessibilityIdentifier("fst.song-detail.shop")
        }
    }

    /// Compact art + title shown in the navigation bar once the hero title scrolls
    /// under it: the native form of the PWA's pinned song header.
    ///
    /// Hidden (and removed from VoiceOver) while the hero itself is visible, so the
    /// title is never announced twice.
    private var pinnedTitle: some View {
        HStack(spacing: 8) {
            ArtworkTile(raw: song.albumArt, session: session, size: 28)
                .accessibilityHidden(true)
            MarqueeText(song.title)
                .font(.headline)
                .foregroundStyle(FestivalText.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 240)
        .opacity(heroTitleHidden ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: heroTitleHidden)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHidden(!heroTitleHidden)
        .accessibilityIdentifier("fst.song-detail.pinned-title")
    }
}

/// Decide when Song Detail's navigation bar should carry the song's identity.
enum SongDetailPinnedTitlePolicy {
    /// The hero counts as scrolled away once its title's bottom edge passes the top
    /// of the scroll view.
    ///
    /// SwiftUI's `.scrollView` coordinate space starts at the scroll view's frame,
    /// which sits below the navigation bar (measured on iOS 26.5: frame minY 116 =
    /// the bar's bottom, title maxY 49 at rest), so 0 is the bar's lower edge.
    ///
    /// - Parameter titleMaxY: Hero title's bottom edge in `.scrollView` space.
    /// - Returns: True when the pinned nav-bar title should be visible.
    static func isHeroHidden(titleMaxY: CGFloat) -> Bool {
        titleMaxY.isFinite && titleMaxY <= 0
    }
}

/// Load a visible chart's top ten via the same public, publication-aware API as Solo.
