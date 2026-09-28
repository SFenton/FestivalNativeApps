import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - LeaderboardsScreen

/// `/leaderboards` — top-ten cards per Settings-visible instrument, plus every
/// band size, with a shared rank-by metric picker
/// (`FortniteFestivalWeb/src/pages/leaderboards/LeaderboardsOverviewPage.tsx`).
struct LeaderboardsScreen: View {
    let session: FestivalSession
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

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (API client, selected profile, caches).
    init(session: FestivalSession) {
        self.session = session
    }

    private var rankBy: RankingMetric { RankingMetric(rawValue: rankByRaw) ?? .totalscore }

    private var rankByBinding: Binding<RankingMetric> {
        Binding(get: { rankBy }, set: { rankByRaw = $0.rawValue })
    }

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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(visibleInstruments) { instrument in
                    instrumentCard(instrument)
                }
                ForEach(BandType.allCases) { bandType in
                    bandCard(bandType)
                }
            }
            .padding(16)
        }
        .quickLinks(quickLinks, title: "Leaderboards Quick Links", sections: quickLinkSections)
        .refreshable { await loadAll() }
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
        .task(id: reloadKey) { await loadAll() }
    }

    // MARK: Instrument cards

    @ViewBuilder
    private func instrumentCard(_ instrument: Instrument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                InstrumentIcon(instrument, size: 22)
                FestivalSectionHeader(instrument.label, subtitle: rankBy.label)
            }
            switch instrumentStates[instrument] ?? .loading {
            case .loading:
                RankingsSkeletonRows(count: 5)
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "leaderboards.\(instrument.rawValue)") {
                    Task { await loadInstrument(instrument, rankBy: rankBy) }
                }
            case let .loaded(payload):
                if payload.rankings.entries.isEmpty {
                    cardEmpty("No ranked \(instrument.label) players yet.")
                } else {
                    VStack(spacing: 4) {
                        ForEach(payload.rankings.entries) { entry in
                            AccountRankingRow(
                                entry: entry, metric: rankBy,
                                isSelected: isSelectedAccount(entry.accountId)
                            )
                        }
                    }
                }
                spotlightSection(instrument: instrument, entries: payload.rankings.entries)
                if !payload.rankings.entries.isEmpty {
                    viewAllLink(
                        AppRoute.fullRankings(instrument: instrument, rankBy: rankByRaw),
                        id: "fst.leaderboards.card.\(instrument.rawValue).view-all"
                    )
                }
            }
        }
        .padding(16)
        .festivalGlass(.card)
        // `.contain` must precede `.accessibilityIdentifier` on a container that
        // wraps interactive children (rows, "View All"): without it, the
        // container's own identifier shadows every descendant's, and
        // `AccountRankingRow`'s `fst.rankings.row.<accountId>` never reaches the
        // accessibility tree. `.contain` keeps each child its own element while
        // still letting the card itself carry an identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.leaderboards.card.\(instrument.rawValue)")
        .quickLinkSection(Self.quickLink(for: instrument))
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
                    .padding(.top, 4)
                } else {
                    RankingSpotlightLoadingRow()
                        .padding(.top, 4)
                        .accessibilityIdentifier("fst.leaderboards.card.\(instrument.rawValue).spotlight.loading")
                }
            case .unranked:
                RankingSpotlightUnrankedRow(message: "Not yet ranked on \(instrument.label).")
                    .padding(.top, 4)
                    .accessibilityIdentifier("fst.leaderboards.card.\(instrument.rawValue).spotlight.unranked")
            case let .footer(entry):
                AccountRankingRow(entry: entry, metric: rankBy, isSelected: true)
                    .padding(.top, 4)
                    .accessibilityIdentifier("fst.leaderboards.card.\(instrument.rawValue).spotlight")
            }
        }
    }

    // MARK: Band cards

    @ViewBuilder
    private func bandCard(_ bandType: BandType) -> some View {
        let metric = rankBy.bandMetric
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(BrandTokens.textSecondary)
                    .frame(width: 22, height: 22)
                FestivalSectionHeader(bandType.label, subtitle: metric.label)
            }
            switch bandStates[bandType] ?? .loading {
            case .loading:
                RankingsSkeletonRows(count: 5)
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "leaderboards.\(bandType.rawValue)") {
                    Task { await loadBand(bandType, rankBy: metric) }
                }
            case let .loaded(payload):
                if payload.rankings.entries.isEmpty {
                    cardEmpty("No ranked \(bandType.label.lowercased()) yet.")
                } else {
                    VStack(spacing: 4) {
                        ForEach(payload.rankings.entries) { entry in
                            BandRankingRow(entry: entry, metric: metric, bandType: bandType)
                        }
                    }
                    viewAllLink(
                        AppRoute.bandRankings(bandType: bandType.rawValue),
                        id: "fst.leaderboards.band-card.\(bandType.rawValue).view-all"
                    )
                }
            }
        }
        .padding(16)
        .festivalGlass(.card)
        // See the matching comment in `instrumentCard`: `.contain` keeps
        // `BandRankingRow`'s own identifier from being shadowed by the card's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.leaderboards.band-card.\(bandType.rawValue)")
        .quickLinkSection(Self.quickLink(for: bandType))
    }

    // MARK: Shared card fragments

    private func cardEmpty(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(BrandTokens.textSecondary)
    }

    private func viewAllLink(_ route: AppRoute, id: String) -> some View {
        NavigationLink(value: route) {
            Text("View All")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .foregroundStyle(BrandTokens.accentBlue)
        .accessibilityIdentifier(id)
    }

    // MARK: Loading

    /// Refresh every visible instrument card and every band card.
    private func loadAll() async {
        for instrument in visibleInstruments {
            await loadInstrument(instrument, rankBy: rankBy)
        }
        let metric = rankBy.bandMetric
        for bandType in BandType.allCases {
            await loadBand(bandType, rankBy: metric)
        }
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
