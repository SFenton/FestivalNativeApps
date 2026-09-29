import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - LeaderboardsScreen

/// `/leaderboards` — top-ten cards per Settings-visible instrument, plus every
/// band size, with a shared rank-by metric picker
/// (`FortniteFestivalWeb/src/pages/leaderboards/LeaderboardsOverviewPage.tsx`).
struct LeaderboardsScreen: View {
    let session: FestivalSession
    @Environment(\.deviceLayout) private var layout
    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true
    @AppStorage("fst.leaderboards.rankBy") private var rankByRaw = RankingMetric.totalscore.rawValue
    @State private var instrumentStates: [Instrument: RankLoadState<RankingsPayload>] = [:]
    @State private var bandStates: [BandType: RankLoadState<BandRankingsPayload>] = [:]
    /// The selected player's own row on each instrument's board, fetched only when
    /// they are not already among the loaded top ten — see `spotlightSection(_:entries:)`.
    /// Band cards have no equivalent: the app has no persisted "selected band"
    /// identity yet (unlike the web client's `useSelectedProfile()` band branch),
    /// so band spotlighting is intentionally not ported this pass — see
    /// `.agents/pages/leaderboards/ios.md`.
    @State private var spotlightStates: [Instrument: RankLoadState<PlayerInstrumentRankingPayload>] = [:]
    @State private var quickLinks = QuickLinksController()
    /// `reloadKey` whose cards finished loading; a reappearance with the same key keeps them.
    @State private var loadedKey: String?
    /// The first read of every card settled: until then only a spinner shows, then the
    /// cards fade in with the web stagger (operator batch 6.41).
    @State private var firstLoadDone = false

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (API client, selected profile, caches).
    init(session: FestivalSession) {
        self.session = session
    }

    private var rankBy: RankingMetric { RankingMetric(rawValue: rankByRaw) ?? .totalscore }

    /// Rank-by selection projected from the stored raw value by key path.
    ///
    /// A key-path projection of the `@AppStorage` binding compares equal across body
    /// passes; a `Binding(get:set:)` never does, so the toolbar `Menu` was rebuilt on every
    /// parent update (each rebuild animates in the iPhone Duo rail).
    private var rankByBinding: Binding<RankingMetric> { $rankByRaw.rankingMetricSelection }

    /// Mirror the tab root's Filter menu without depending on its own state.
    private var visibleInstruments: [Instrument] {
        let shown: Set<Instrument> = {
            let preferences: [(Instrument, Bool)] = [
                (.lead, showLead), (.bass, showBass), (.drums, showDrums),
                (.vocals, showVocals), (.proLead, showProLead), (.proBass, showProBass),
                (.karaoke, showKaraoke), (.proCymbals, showProCymbals),
                (.proDrums, showProDrums),
            ]
            return Set(preferences.compactMap { $0.1 ? $0.0 : nil })
        }()
        return Instrument.allCases.filter(shown.contains)
    }

    /// Reload every card whenever the metric, the visible instrument set, or the
    /// selected player changes (the last so a new selection's spotlight loads).
    private var reloadKey: String {
        "\(rankByRaw)|\(visibleInstruments.map(\.rawValue).joined(separator: ","))|" +
            (session.selectedPlayer?.accountId ?? "")
    }

    /// One quick link per card, in card order (web ids `instrument:<key>` / `band:<type>`).
    private var quickLinkSections: [QuickLinkSection] {
        visibleInstruments.map { Self.quickLink(for: $0) } + BandType.allCases.map { Self.quickLink(for: $0) }
    }

    /// Quick link for an instrument card.
    ///
    /// - Parameter instrument: Card's instrument.
    /// - Returns: Section with the web id and label.
    static func quickLink(for instrument: Instrument) -> QuickLinkSection {
        QuickLinkSection(id: "instrument:\(instrument.rawValue)", title: instrument.label, icon: .instrument(instrument))
    }

    /// Quick link for a band card.
    ///
    /// - Parameter bandType: Card's band size.
    /// - Returns: Section with the web id and label.
    static func quickLink(for bandType: BandType) -> QuickLinkSection {
        QuickLinkSection(id: "band:\(bandType.rawValue)", title: bandType.label, icon: .system("person.3.fill"))
    }

    /// Tab-root page actions must precede the shared bell/avatar capsule; iOS pins
    /// `.primaryAction` to the trailing edge, so use `.topBarTrailing` there.
    private static var pageActionPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    /// Two flexible columns on a regular-width window (Duo unfolded, iPad): the
    /// overview's instrument/band cards read as a dashboard rather than one very
    /// wide column (`.agents/design/apple/duo.md` "Compete, Statistics, … dashboards
    /// use 2-column grids"). Compact windows (iPhone, Duo folded) keep the single
    /// column unchanged.
    private var regularWidthColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]
    }

    @ViewBuilder
    private var cards: some View {
        // The fade sits inside each card, under its Quick Links section id, so the lazy
        // stack can still scroll to a card it has not built yet.
        ForEach(Array(visibleInstruments.enumerated()), id: \.element) { index, instrument in
            instrumentCard(instrument, fadeIndex: index)
        }
        ForEach(Array(BandType.allCases.enumerated()), id: \.element) { index, bandType in
            bandCard(bandType, fadeIndex: visibleInstruments.count + index)
        }
    }

    var body: some View {
        Group {
            if firstLoadDone {
                loadedScroll
            } else {
                FestivalLoadingView(accessibilityLabel: "Loading Leaderboards")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("fst.leaderboards.loading")
            }
        }
        .festivalBackground(.carousel, session: session)
        .navigationTitle("Leaderboards")
        .toolbar {
            ToolbarItem(placement: Self.pageActionPlacement) {
                RankByMenu(selection: rankByBinding)
            }
            QuickLinksToolbarItem(quickLinks)
            FestivalRootTrailingItems(session: session)
        }
        .festivalProvidesRootTrailingItems()
        .task(id: reloadKey) {
            // `.task` restarts on every reappearance (e.g. Back from a player). Reloading
            // then reset all cards and re-rendered the page and its toolbar for ~0.5 s,
            // which the iPhone Duo rail showed as jitter (Lane W1). Pull to refresh still
            // reloads.
            guard loadedKey != reloadKey else { return }
            let key = reloadKey
            await loadAll()
            guard !Task.isCancelled else { return }
            firstLoadDone = true
            if allCardsLoaded { loadedKey = key }
        }
    }

    private var loadedScroll: some View {
        ScrollView {
            Group {
                if layout.widthClass == .regular {
                    LazyVGrid(columns: regularWidthColumns, alignment: .leading, spacing: 24) {
                        cards
                    }
                } else {
                    LazyVStack(spacing: 24) {
                        cards
                    }
                }
            }
            .padding(16)
        }
        .quickLinks(quickLinks, title: "Leaderboards Quick Links", sections: quickLinkSections)
        .refreshable { await loadAll() }
    }

    // MARK: Instrument cards

    /// One instrument's top ten: an icon header, then compact glass rows and the
    /// "View all rankings (N)" row — the web's `RankingCard.tsx` layout, where the
    /// rows themselves are the frosted cards and the section has no outer card.
    @ViewBuilder
    private func instrumentCard(_ instrument: Instrument, fadeIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            cardHeader(instrument.label) {
                InstrumentIcon(instrument, size: 36)
            }
            switch instrumentStates[instrument] ?? .loading {
            case .loading:
                RankingsSkeletonRows(count: 5, glassRows: true)
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "leaderboards.\(instrument.rawValue)") {
                    Task { await loadInstrument(instrument, rankBy: rankBy) }
                }
                .modifier(CardMessageSurface())
            case let .loaded(payload):
                if payload.rankings.entries.isEmpty {
                    cardEmpty("No ranked \(instrument.label) players yet.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(payload.rankings.entries) { entry in
                            AccountRankingRow(
                                entry: entry, metric: rankBy,
                                isSelected: isSelectedAccount(entry.accountId), glassSurface: true
                            )
                        }
                    }
                    .festivalFadeInOnAppear()
                }
                spotlightSection(instrument: instrument, entries: payload.rankings.entries)
                if !payload.rankings.entries.isEmpty {
                    viewAllLink(
                        AppRoute.fullRankings(instrument: instrument, rankBy: rankByRaw),
                        title: RankingsCountText.viewAllRankings(
                            totalAccounts: payload.rankings.totalAccounts
                        ),
                        id: "fst.leaderboards.card.\(instrument.rawValue).view-all"
                    )
                }
            }
        }
        // `.contain` must precede `.accessibilityIdentifier` on a container that
        // wraps interactive children (rows, "View All"): without it, the
        // container's own identifier shadows every descendant's, and
        // `AccountRankingRow`'s `fst.rankings.row.<accountId>` never reaches the
        // accessibility tree. `.contain` keeps each child its own element while
        // still letting the card itself carry an identifier.
        .festivalFadeIn(isLoaded: true, index: fadeIndex)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.leaderboards.card.\(instrument.rawValue)")
        .quickLinkSection(Self.quickLink(for: instrument))
    }

    /// Section header above the rows: the instrument icon and name (web
    /// `InstrumentHeader` MD), or the band size's name alone. No metric subtitle
    /// (operator, 2026-09-28): the active metric lives in the toolbar menu.
    ///
    /// - Parameters:
    ///   - title: Instrument or band-size name.
    ///   - icon: 36 pt instrument icon, or `EmptyView` for band sizes.
    /// - Returns: A single-line header.
    private func cardHeader<Icon: View>(
        _ title: String, @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 10) {
            icon()
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(FestivalText.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
        .padding(.bottom, 2)
    }

    // MARK: Selected-player spotlight

    /// Whether `accountId` is the currently selected player, matching case-insensitively
    /// as the wire's account ids sometimes vary in casing.
    ///
    /// - Parameter accountId: Row's account id.
    /// - Returns: True only when a player is selected and it is this account.
    private func isSelectedAccount(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    /// Show the selected player's own row below one instrument's top ten when they
    /// are not already visible among `entries`, mirroring the web client's
    /// `RankingCard` spotlight footer (`RankingCard.tsx:97-102`).
    ///
    /// - Parameters:
    ///   - instrument: Card's instrument.
    ///   - entries: This card's currently loaded top-ten rows.
    @ViewBuilder
    private func spotlightSection(instrument: Instrument, entries: [AccountRankingEntry]) -> some View {
        if let accountId = session.selectedPlayer?.accountId {
            let source: RankingSpotlightSource = {
                switch spotlightStates[instrument] {
                case .none, .loading: return .notLoaded
                case let .loaded(payload): return payload.ranking.map { .available($0.entry) } ?? .unranked
                case .failed: return .notLoaded
                }
            }()
            switch RankingSpotlight.placement(
                selectedAccountId: accountId, visibleEntries: entries, source: source
            ) {
            case .none, .inline:
                EmptyView()
            case .pending:
                if case let .failed(issue) = spotlightStates[instrument] {
                    ServiceStatusInline(issue, scope: "leaderboards.spotlight.\(instrument.rawValue)") {
                        Task { await loadSpotlight(instrument) }
                    }
                    .modifier(CardMessageSurface())
                } else {
                    RankingSpotlightLoadingRow()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("fst.leaderboards.card.\(instrument.rawValue).spotlight.loading")
                }
            case .unranked:
                RankingSpotlightUnrankedRow(message: "Not yet ranked on \(instrument.label).")
                    .modifier(CardMessageSurface())
                    .accessibilityIdentifier("fst.leaderboards.card.\(instrument.rawValue).spotlight.unranked")
            case let .footer(entry):
                AccountRankingRow(entry: entry, metric: rankBy, isSelected: true, glassSurface: true)
                    .festivalFadeInOnAppear()
                    .accessibilityIdentifier("fst.leaderboards.card.\(instrument.rawValue).spotlight")
            }
        }
    }

    // MARK: Band cards

    @ViewBuilder
    private func bandCard(_ bandType: BandType, fadeIndex: Int) -> some View {
        let metric = rankBy.bandMetric
        VStack(alignment: .leading, spacing: 6) {
            cardHeader(bandType.label) {
                EmptyView()
            }
            switch bandStates[bandType] ?? .loading {
            case .loading:
                RankingsSkeletonRows(count: 5, glassRows: true)
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "leaderboards.\(bandType.rawValue)") {
                    Task { await loadBand(bandType, rankBy: metric) }
                }
                .modifier(CardMessageSurface())
            case let .loaded(payload):
                if payload.rankings.entries.isEmpty {
                    cardEmpty("No ranked \(bandType.label.lowercased()) yet.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(payload.rankings.entries) { entry in
                            BandRankingRow(entry: entry, metric: metric, bandType: bandType, glassSurface: true)
                        }
                    }
                    .festivalFadeInOnAppear()
                    viewAllLink(
                        AppRoute.bandRankings(bandType: bandType.rawValue),
                        title: RankingsCountText.viewAllBandRankings(
                            totalTeams: payload.rankings.totalTeams
                        ),
                        id: "fst.leaderboards.band-card.\(bandType.rawValue).view-all"
                    )
                }
            }
        }
        // See the matching comment in `instrumentCard`: `.contain` keeps
        // `BandRankingRow`'s own identifier from being shadowed by the card's.
        .festivalFadeIn(isLoaded: true, index: fadeIndex)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.leaderboards.band-card.\(bandType.rawValue)")
        .quickLinkSection(Self.quickLink(for: bandType))
    }

    // MARK: Shared card fragments

    private func cardEmpty(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(FestivalText.primary)
            .modifier(CardMessageSurface())
    }

    /// The card's last row, "View all rankings (868,901)" (web `viewAllButton`), as a
    /// purple glass button below the top ten (and below the selected player's
    /// spotlight row when they are outside it).
    ///
    /// - Parameters:
    ///   - route: Full board to push.
    ///   - title: Label including the ranked count when known.
    ///   - id: Existing per-card `…view-all` identifier.
    /// - Returns: A full-width glass navigation row.
    private func viewAllLink(_ route: AppRoute, title: String, id: String) -> some View {
        NavigationLink(value: route) {
            PurpleActionLabel(title: title)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: Loading

    /// Refresh every visible instrument card and every band card.
    /// True when every instrument and band card holds data (a failed card retries on return).
    private var allCardsLoaded: Bool {
        let cards = visibleInstruments.map { instrumentStates[$0].map(Self.isLoaded) ?? false }
            + BandType.allCases.map { bandStates[$0].map(Self.isLoaded) ?? false }
        return !cards.contains(false)
    }

    /// Whether a card state holds data.
    ///
    /// - Parameter state: Card load state.
    /// - Returns: True for `.loaded`.
    private static func isLoaded<Payload>(_ state: RankLoadState<Payload>) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    /// Read every card in parallel and apply the results together (no card pops in on
    /// its own; a metric change keeps the old cards until the new ones are ready).
    private func loadAll() async {
        let cards = await LeaderboardsPreloader.load(
            session: session, instruments: visibleInstruments, rankBy: rankBy, bandMetric: rankBy.bandMetric
        )
        guard !Task.isCancelled else { return }
        instrumentStates = cards.instruments
        bandStates = cards.bands
        spotlightStates = cards.spotlights
    }

    /// Load one instrument's top-ten card.
    ///
    /// - Parameters:
    ///   - instrument: Chart to request.
    ///   - rankBy: Selected sort metric.
    private func loadInstrument(_ instrument: Instrument, rankBy: RankingMetric) async {
        instrumentStates[instrument] = .loading
        do {
            let payload = try await session.rankings(
                instrument: instrument, rankBy: rankBy, page: 1, pageSize: 10
            )
            instrumentStates[instrument] = .loaded(payload)
            if let selected = session.selectedPlayer?.accountId,
               !payload.rankings.entries.contains(where: {
                   $0.accountId.caseInsensitiveCompare(selected) == .orderedSame
               }) {
                await loadSpotlight(instrument)
            } else {
                spotlightStates[instrument] = nil
            }
        } catch {
            instrumentStates[instrument] = .failed(ServiceIssue(error))
        }
    }

    /// Read the selected player's own row on one instrument's board, only called
    /// when they are not already among the loaded top ten.
    ///
    /// - Parameter instrument: Chart to look up.
    private func loadSpotlight(_ instrument: Instrument) async {
        guard let accountId = session.selectedPlayer?.accountId else {
            spotlightStates[instrument] = nil
            return
        }
        spotlightStates[instrument] = .loading
        do {
            let payload = try await session.playerInstrumentRanking(
                instrument: instrument, accountId: accountId
            )
            spotlightStates[instrument] = .loaded(payload)
        } catch {
            spotlightStates[instrument] = .failed(ServiceIssue(error))
        }
    }

    /// Load one band size's top-ten card.
    ///
    /// - Parameters:
    ///   - bandType: Band size to request.
    ///   - rankBy: Selected sort metric, already narrowed to band-safe cases.
    private func loadBand(_ bandType: BandType, rankBy: BandRankingMetric) async {
        bandStates[bandType] = .loading
        do {
            let payload = try await session.bandRankings(
                bandType: bandType, rankBy: rankBy, page: 1, pageSize: 10
            )
            bandStates[bandType] = .loaded(payload)
        } catch {
            bandStates[bandType] = .failed(ServiceIssue(error))
        }
    }
}

// MARK: - Card message surface

/// Glass row for a card's non-row states (failure, empty, unranked), so they sit on
/// the same surface as the rows they replace.
private struct CardMessageSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .festivalGlass(.card, cornerRadius: 12)
    }
}

// MARK: - Rank-by storage projection

private extension String {
    /// This raw value as a `RankingMetric` (Total Score when unrecognised); writing stores
    /// the metric's raw value. Used as a key path so the binding stays comparable.
    var rankingMetricSelection: RankingMetric {
        get { RankingMetric(rawValue: self) ?? .totalscore }
        set { self = newValue.rawValue }
    }
}
