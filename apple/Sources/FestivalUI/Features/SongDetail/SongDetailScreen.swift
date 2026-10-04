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
    /// Duos/Trios/Quads previews from the one `/bands/all` read.
    @State private var bandPreviews: SongBandPreviewState = .loading
    /// Publication and player the band previews were read for.
    @State private var bandKey: BandKey?
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
    /// The page's width (the web viewport), for Score History's season column (issue #32).
    @State private var pageWidth: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Section chrome: the iPhone Duo vertical bar needs a titled symbol Shop item.
    @Environment(\.deviceLayout) private var deviceLayout
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

    /// What the page's first-appearance reads depend on.
    private struct GateKey: Hashable {
        let publicationRevision: Int
        let accountId: String?
        let leeway: Double?
    }

    /// What the band previews depend on (not leeway: band scores are unfiltered).
    private struct BandKey: Hashable {
        let publicationRevision: Int
        let accountId: String?
    }

    private var gateKey: GateKey {
        GateKey(
            publicationRevision: session.publicationRevision,
            accountId: session.selectedPlayer?.accountId,
            leeway: filterInvalidScores ? (leeway * 10).rounded() / 10 : nil
        )
    }

    private var previewInstruments: [Instrument] { charted.filter(visibleInstruments.contains) }

    /// Whether the Score History section is drawn (a selected player with rows).
    private var showsScoreHistory: Bool { session.selectedPlayer != nil && !historyEntries.isEmpty }

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

    /// Intensity, Score History (when shown), one entry per visible leaderboard card,
    /// then Duos/Trios/Quads (web `band-<bandType>`): the page's top-to-bottom order
    /// (`.agents/controls/quick-links/ios.md`). Uses the same predicates as the body so
    /// the menu cannot list a section the page does not draw.
    private var quickLinkSections: [QuickLinkSection] {
        [QuickLinkSection(id: "intensity", title: "Intensity", icon: .system("chart.bar.fill"))]
            + (showsScoreHistory ? [
                QuickLinkSection(id: "score-history", title: "Score History", icon: .system("chart.line.uptrend.xyaxis")),
            ] : [])
            + previewInstruments.map { instrument in
                QuickLinkSection(
                    id: "instrument-\(instrument.rawValue)", title: instrument.label,
                    icon: .instrument(instrument)
                )
            }
            + BandType.allCases.map(Self.bandQuickLink)
    }

    /// Quick Links entry for one band-size preview section.
    ///
    /// - Parameter bandType: Band size.
    /// - Returns: The section's menu entry (web id `band-<bandType>`).
    private static func bandQuickLink(_ bandType: BandType) -> QuickLinkSection {
        let symbol = switch bandType {
        case .duets: "person.2.fill"
        case .trios: "person.3.fill"
        case .quad: "person.3.sequence.fill"
        }
        return QuickLinkSection(id: "band-\(bandType.rawValue)", title: bandType.label, icon: .system(symbol))
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
        let _ = MainThreadStallMonitor.count("songdetail.body")
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
        // iPhone tab-bar accessory (issue #92): Item Shop, then Paths, then Quick Links.
        .festivalPageTool(
            token: [shopOffer?.shopUrl.absoluteString ?? "", shopTone.map { "\($0)" } ?? ""],
            order: PageToolOrder.primary, isEnabled: shopOffer != nil
        ) {
            if let offer = shopOffer { shopAction(offer, fillsSlot: true) }
        }
        .festivalPageTool(
            token: "paths", order: PageToolOrder.secondary, isEnabled: !pathInstruments.isEmpty
        ) {
            pathsButton
        }
        .macSongCommands(macSongCommands)
        #if os(macOS)
        #if DEBUG
        // `tools/mac_app.py command song:paths` (the Song menu needs a key window).
        .onReceive(NotificationCenter.default.publisher(for: MacDebugHooks.openPathsName)) { _ in
            if !pathInstruments.isEmpty { pathsPresented = true }
        }
        #endif
        #endif
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

    /// The toolbar's Paths and Item Shop tools for the Song menu (macOS, iPadOS).
    private var macSongCommands: MacSongCommands {
        let presented: Binding<Bool> = $pathsPresented
        var commands = MacSongCommands(songId: song.songId, paths: nil, shopURL: shopOffer?.shopUrl)
        if !pathInstruments.isEmpty {
            commands.paths = { presented.wrappedValue = true }
        }
        return commands
    }

    /// Song Detail's bar items.
    ///
    /// In the iPhone Duo vertical bar the pinned title (a custom view) is left out: the
    /// rail never draws it. Item Shop and Paths carry high visibility priority so they
    /// stay in the rail ahead of Quick Links (`/duo` D4, operator 2026-10-02: page-unique
    /// actions first; HIG iPhone Duo: "Set visibility priority by group").
    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        #if os(iOS)
        if !deviceLayout.sectionChrome.isVerticalBar {
            ToolbarItem(placement: .principal) {
                pinnedTitle
            }
        }
        #endif
        if pageTools == nil, let offer = shopOffer {
            ToolbarItem(placement: .festivalPageAction) {
                shopAction(offer)
            }
            .songDetailPagePriority()
        }
        if pageTools == nil, !pathInstruments.isEmpty {
            ToolbarItem(placement: .festivalPageAction) {
                pathsButton
            }
            .songDetailPagePriority()
        }
        QuickLinksToolbarItem(quickLinks)
    }

    /// Opens the Paths sheet.
    private var pathsButton: some View {
        Button {
            pathsPresented = true
        } label: {
            Label("Paths", systemImage: "map")
        }
        .accessibilityIdentifier("fst.song-detail.paths")
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
                    .festivalCard(cornerRadius: 16)
                }
                .accessibilityIdentifier("fst.song-detail.intensity")
                .festivalFadeIn(isLoaded: true, index: 1)
                .quickLinkSection(id: "intensity", title: "Intensity", symbol: "chart.bar.fill")

                if showsScoreHistory {
                    SongScoreHistorySection(
                        entries: historyEntries, pool: previewInstruments,
                        keyboardIcon: song.usesKeyboardIcon,
                        instrument: $historyInstrument, expanded: $historyExpanded,
                        viewportWidth: pageWidth, currentSeason: session.catalogCurrentSeason
                    )
                    .festivalFadeIn(isLoaded: true, index: 2)
                    .id(SongScoreHistorySection.anchor)
                    .quickLinkSection(
                        id: "score-history", title: "Score History", symbol: "chart.line.uptrend.xyaxis"
                    )
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
                            .festivalFadeIn(isLoaded: true, index: index + 3)
                            .quickLinkSection(QuickLinkSection(
                                id: "instrument-\(instrument.rawValue)", title: instrument.label,
                                icon: .instrument(instrument)
                            ))
                        }
                    }
                }

                ForEach(Array(BandType.allCases.enumerated()), id: \.element) { index, bandType in
                    SongBandPreviewSection(
                        song: song, bandType: bandType, state: bandPreviews,
                        onRetry: { Task { await reloadBands() } }
                    )
                    .festivalFadeIn(isLoaded: true, index: previewInstruments.count + index + 3)
                    .quickLinkSection(Self.bandQuickLink(bandType))
                }
            }
            .padding(16)
            // Only what is on screen at load fades; lazily built cards scrolled into
            // view afterwards appear without a fade (issue #30).
            .festivalFadeInScope()
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { width in
            pageWidth = width
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
            async let bands: Void = loadBandsIfNeeded()
            await loadHistory()
            await bands
            if !Task.isCancelled { loadedGate = key }
            return
        }
        async let history: Void = loadHistory()
        async let bands: Void = loadBandsIfNeeded()
        let previews = await SongDetailPreloader.previews(
            session: session, song: song, instruments: previewInstruments, leeway: key.leeway
        )
        await history
        await bands
        guard !Task.isCancelled else { return }
        previewPreloads = previews
        loadedGate = key
        ready = true
    }

    /// Read the band previews when the publication or selected player changed since the
    /// last read. Rows already shown stay until the new read settles.
    private func loadBandsIfNeeded() async {
        let key = BandKey(
            publicationRevision: session.publicationRevision,
            accountId: session.selectedPlayer?.accountId
        )
        guard bandKey != key else { return }
        guard let state = await SongBandPreviewLoader.load(
            session: session, songId: song.songId, accountId: key.accountId
        ) else { return }
        bandPreviews = state
        bandKey = key
    }

    /// Retry: show the spinner and read the band previews again.
    private func reloadBands() async {
        bandPreviews = .loading
        bandKey = nil
        await loadBandsIfNeeded()
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
    /// - Parameters:
    ///   - offer: Validated Shop row for this song.
    ///   - fillsSlot: In the tab-bar accessory: the breathing glyph's hit target fills
    ///     its slot (at least 44×44 pt).
    /// - Returns: Toolbar link with a spoken status.
    @ViewBuilder
    private func shopAction(_ offer: ShopSong, fillsSlot: Bool = false) -> some View {
        switch SongDetailShopActionStyle.resolve(tone: shopTone, chrome: deviceLayout.sectionChrome) {
        case let .breathing(tone):
            Link(destination: offer.shopUrl) {
                Image(systemName: "bag")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .frame(width: 34, height: 34)
                    .modifier(ShopStatusBreathe(tone: tone))
                    // In the tab-bar accessory the whole slot is the hit target (44 pt+).
                    .frame(maxWidth: fillsSlot ? .infinity : nil, maxHeight: fillsSlot ? .infinity : nil)
                    .frame(minWidth: fillsSlot ? 44 : nil, minHeight: fillsSlot ? 44 : nil)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Item Shop, \(tone.spokenStatus)")
            .accessibilityIdentifier("fst.song-detail.shop")
        case let .titled(spokenLabel):
            Link(destination: offer.shopUrl) {
                Label("Item Shop", systemImage: "bag")
            }
            .accessibilityLabel(spokenLabel)
            .accessibilityIdentifier("fst.song-detail.shop")
        }
    }

    /// Compact art + title shown in the navigation bar once the hero title scrolls
    /// under it: the native form of the PWA's pinned song header.
    ///
    /// Built only while the hero is scrolled away, so the title is never announced
    /// twice. A transparent copy kept in the tree was still read (and audited as
    /// invisible, fixed-size text) on iPadOS: the bar hosts this view outside SwiftUI's
    /// accessibility hiding. A `.hidden()` placeholder of the same text keeps the bar's
    /// layout from jumping as the title appears.
    private var pinnedTitle: some View {
        ZStack(alignment: .leading) {
            Text(song.title)
                .font(.headline)
                .lineLimit(1)
                .padding(.leading, 36)
                .hidden()
            if heroTitleHidden {
                HStack(spacing: 8) {
                    ArtworkTile(raw: song.albumArt, session: session, size: 28)
                        .accessibilityHidden(true)
                    MarqueeText(song.title)
                        .font(.headline)
                        .foregroundStyle(FestivalText.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fst.song-detail.pinned-title")
            }
        }
        .frame(maxWidth: 240)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: heroTitleHidden)
        // A bar title stays on one line at every text size.
        .environment(\.marqueeWrapsAtAccessibilitySizes, false)
    }
}

/// High visibility priority for Song Detail's page-unique actions (iOS 27+).
private extension ToolbarContent {
    @ToolbarContentBuilder
    func songDetailPagePriority() -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            visibilityPriority(.high)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// How Song Detail draws its official Item Shop toolbar action.
///
/// The breathing status fill is a custom image view. The iPhone Duo vertical bar keeps
/// custom-view items horizontal and dropped this one from both the rail and its
/// overflow menu, so the action was unreachable folded (HIG Designing for iPhone Duo:
/// "Give every non-text-only item a title and symbol so the system can choose its
/// representation"). In a vertical bar it is a titled `bag` symbol; the status stays in
/// the spoken label.
enum SongDetailShopActionStyle: Equatable, Sendable {
    /// Image-only action whose fill breathes in the status colour (horizontal bars).
    case breathing(ShopStatusTone)
    /// Standard `Label` item with this VoiceOver label.
    case titled(spokenLabel: String)

    /// Choose the style for the current chrome.
    ///
    /// - Parameters:
    ///   - tone: Shop status tone, or nil when highlighting is off.
    ///   - chrome: Current section chrome.
    /// - Returns: Breathing only with a tone outside the vertical bar; titled otherwise.
    static func resolve(tone: ShopStatusTone?, chrome: DeviceLayout.SectionChrome) -> Self {
        if let tone, !chrome.isVerticalBar { return .breathing(tone) }
        return .titled(spokenLabel: tone.map { "Item Shop, \($0.spokenStatus)" } ?? "Item Shop")
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
