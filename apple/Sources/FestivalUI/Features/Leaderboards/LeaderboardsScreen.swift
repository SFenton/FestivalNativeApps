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

    /// Reload every card whenever the metric or the visible instrument set changes.
    private var reloadKey: String {
        "\(rankByRaw)|\(visibleInstruments.map(\.rawValue).joined(separator: ","))"
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
                            AccountRankingRow(entry: entry, metric: rankBy)
                        }
                    }
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
        } catch {
            instrumentStates[instrument] = .failed(ServiceIssue(error))
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
