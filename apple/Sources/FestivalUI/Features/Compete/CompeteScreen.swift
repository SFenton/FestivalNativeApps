import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - CompeteScreen

/// `/compete` — phone hub combining Leaderboards and Rivals; this is the phone
/// tab shown once a player is selected (see `FestivalRootView`).
///
/// Ports the web's `CompetePage`: a Leaderboards section (live Top-5 preview per
/// ranking scope: each family's within-group combo such as "Lead + Bass", then each
/// Settings-visible instrument, web `resolveSupportedRankingScopes`, #602; reusing Lane L's `AccountRankingRow`/`RankLoadState`
/// from `Features/Leaderboards/RankingsSupport.swift`) and a Rivals section
/// (reusing `RivalInstrumentSongCard`). Like the web, the whole page loads behind one
/// spinner, then its headers and cards fade in on one stagger (``CompeteHubModel``,
/// load-transition R1, #354). No player selected → `RivalsChooseProfileState`. See
/// `.agents/pages/compete/ios.md`.
struct CompeteScreen: View {
    let session: FestivalSession
    @State private var quickLinks = QuickLinksController()
    @State private var model = CompeteHubModel()
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var layout
    private var visible = VisibleInstrumentsReader()

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (API client, selected profile, caches).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                hub
            }
        }
        .festivalNavigationTitle("Compete")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            QuickLinksToolbarItem(quickLinks)
            FestivalRootTrailingItems(session: session)
        }
        .festivalProvidesRootTrailingItems()
    }

    private var loadKey: CompetePageLoadKey {
        CompetePageLoadKey(instruments: visible.instruments, session: session)
    }

    /// One page gate for every read (web `usePageTransition` on `liveReady`): a centred
    /// spinner and no headers until every leaderboard and rivals read settles, then the
    /// spinner fades and the page fades in. A return with the page loaded keeps it
    /// (``ReappearanceLoadGate`` in the model), so it shows at once without a spinner.
    @ViewBuilder private var hub: some View {
        let key = loadKey
        FestivalReloadGate(
            key: key, isLoading: model.isLoading(for: key),
            spinnerLabel: "Loading Compete", spinnerIdentifier: "fst.compete.loading"
        ) {
            if let issue = model.fullPageIssue(for: key) {
                // Web: every leaderboard failing shows one page-wide error.
                ServiceStatusView(issue, title: "Compete unavailable", scope: "compete") { retry(key) }
            } else {
                content
            }
        }
        .task(id: key) { await model.load(key, session: session) }
        // The page gate starts over for another account, so it never reveals the previous
        // account's cards (`.agents/platforms/apple/architecture.md`, "Per-entity screens").
        .id(session.selectedPlayer?.accountId)
        .modifier(CompeteTitleDisplayMode(dualSource: DualSourcePolicy.isActive(layout)))
    }

    @ViewBuilder private var content: some View {
        // iPhone Duo inner display, portrait: leaderboards and rivals become two
        // swipeable sources stacked around the fold (`CompeteDualSource.swift`).
        DualSourceLayout {
            if DualSourcePolicy.isActive(layout) {
                CompeteLeaderboardsCarousel(
                    session: session, scopes: loadKey.scopes, model: model, retry: retryFailedReads
                )
            } else {
                stackedHub
            }
        } secondary: {
            CompeteRivalsCarousel(scopes: loadKey.scopes, model: model, retry: retryFailedReads)
        }
        // The Duo panes' one first-load window, rushed by a swipe in either carousel
        // (load-transition R5). The stacked hub installs its own inside its scroll view.
        .festivalNestedFadeInScope()
    }

    /// Read again whatever failed; the page gate shows its spinner until it settles.
    ///
    /// - Parameter key: The page's current key.
    private func retry(_ key: CompetePageLoadKey) {
        Task { await model.load(key, session: session) }
    }

    /// Read again whatever failed for the page's current key.
    private func retryFailedReads() {
        retry(loadKey)
    }

    private var stackedHub: some View {
        ScrollView {
            Group {
                if layout.widthClass == .regular && !DualSourcePolicy.isActive(layout) {
                    // Regular-width columns (Mac, iPad): Leaderboards beside Rivals, the two
                    // halves of Compete side by side instead of one very long column, split
                    // at an iPhone Duo fold in book pose (pattern `hinge-columns`).
                    HingeRow(spacing: 8) {
                        leaderboardsSection.frame(maxWidth: .infinity, alignment: .top)
                        rivalsSection.frame(maxWidth: .infinity, alignment: .top)
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        leaderboardsSection
                        rivalsSection
                    }
                    .padding(.vertical, 12)
                }
            }
            // The page's one first-load window: a scroll rushes the rest (load-transition R5).
            .festivalFadeInScope()
        }
        .quickLinks(quickLinks, title: "Quick Links")
    }

    // MARK: Entrance order

    /// Stagger position of the Leaderboards header; its cards follow in scope order.
    private static let leaderboardsHeaderIndex = 0

    /// Stagger position of the Rivals header (web `useStagger().next()` reading order:
    /// the Leaderboards header, each leaderboard card, then the Rivals header and cards).
    private var rivalsHeaderIndex: Int { loadKey.scopes.count + 1 }

    // MARK: Leaderboards

    /// Like the web's `CompetePage`, there is no Leaderboards overview link here (#36):
    /// each scope's preview, combos included (#602), links to its own full leaderboard,
    /// and the overview stays in the drawer.
    private var leaderboardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader("Leaderboards")
                .padding(.horizontal, 16)
                .festivalFadeIn(isLoaded: true, index: Self.leaderboardsHeaderIndex)
            if visible.instruments.isEmpty {
                FestivalFootnote("Enable at least one instrument in Settings to see leaderboards.")
                    .padding(.horizontal, 16)
                    .festivalFadeIn(isLoaded: true, index: Self.leaderboardsHeaderIndex + 1)
            } else {
                ForEach(Array(loadKey.scopes.enumerated()), id: \.element) { offset, scope in
                    CompeteInstrumentLeaderboardSection(
                        session: session, scope: scope, state: model.boards[scope] ?? .loading,
                        spotlight: model.spotlights[scope],
                        entranceIndex: Self.leaderboardsHeaderIndex + 1 + offset, retry: retryFailedReads
                    )
                }
            }
        }
        .quickLinkSection(id: "leaderboards", title: "Leaderboards", symbol: "trophy.fill")
    }

    // MARK: Rivals

    private var rivalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader("Rivals")
                .padding(.horizontal, 16)
                .festivalFadeIn(isLoaded: true, index: rivalsHeaderIndex)
            if visible.instruments.isEmpty {
                FestivalFootnote("Enable at least one instrument in Settings to see rivals.")
                    .padding(.horizontal, 16)
                    .festivalFadeIn(isLoaded: true, index: rivalsHeaderIndex + 1)
            } else {
                ForEach(Array(loadKey.scopes.enumerated()), id: \.element) { offset, scope in
                    RivalInstrumentSongCard(
                        scope: scope, state: model.rivals[scope] ?? .loading,
                        registersQuickLink: false,
                        emptyMessage: "No rivals found for \(scope.label) yet.",
                        entranceIndex: rivalsHeaderIndex + 1 + offset, retry: retryFailedReads
                    )
                }
            }
        }
        .quickLinkSection(id: "rivals", title: "Rivals", symbol: "person.2.fill")
    }
}

// MARK: - Per-scope leaderboard preview

/// One instrument's or within-group combo's (#602) Top-5 ranking preview, reusing Lane L's `RankLoadState`/
/// `AccountRankingRow` (`Features/Leaderboards/RankingsSupport.swift`) so Compete's
/// rows match `LeaderboardsScreen`'s own overview cards. The page reads it
/// (``CompeteHubModel``) and only builds it once every read settled, so it never shows a
/// spinner of its own (#354).
///
/// When the selected player ranks outside the top five, their own row follows them (web
/// `CompetePage` `playerEntry`) and jumps to their position on the full board
/// (``CompetePreviewSpotlight``, leaderboard-row R7 owner variant, #370).
struct CompeteInstrumentLeaderboardSection: View {
    let session: FestivalSession
    /// The card's board: one instrument, or a within-group combo.
    let scope: RankingScope
    let state: RankLoadState<RankingsPayload>
    /// The selected player's own row, shown apart from the top five; nil when they are
    /// among them, unranked or unknown.
    var spotlight: AccountRankingEntry? = nil
    /// The card's place in the page's first-load stagger.
    var entranceIndex: Int? = nil
    /// Reads the preview again after a failure.
    let retry: () -> Void

    /// Create a preview card for one instrument's or a combo's board.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - scope: The instrument or within-group combo.
    ///   - state: The preview read.
    ///   - spotlight: The selected player's own row shown apart, if any.
    ///   - entranceIndex: The card's place in the page's first-load stagger.
    ///   - retry: Reads the preview again after a failure.
    init(
        session: FestivalSession, scope: RankingScope, state: RankLoadState<RankingsPayload>,
        spotlight: AccountRankingEntry? = nil, entranceIndex: Int? = nil, retry: @escaping () -> Void
    ) {
        self.session = session
        self.scope = scope
        self.state = state
        self.spotlight = spotlight
        self.entranceIndex = entranceIndex
        self.retry = retry
    }

    /// Create a preview card for one instrument's board.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - instrument: The card's instrument.
    ///   - state: The preview read.
    ///   - spotlight: The selected player's own row shown apart, if any.
    ///   - entranceIndex: The card's place in the page's first-load stagger.
    ///   - retry: Reads the preview again after a failure.
    init(
        session: FestivalSession, instrument: Instrument, state: RankLoadState<RankingsPayload>,
        spotlight: AccountRankingEntry? = nil, entranceIndex: Int? = nil, retry: @escaping () -> Void
    ) {
        self.init(
            session: session, scope: .instrument(instrument), state: state,
            spotlight: spotlight, entranceIndex: entranceIndex, retry: retry
        )
    }

    var body: some View {
        // Instrument (or combo) header above the card, never inside it (operator rule).
        VStack(alignment: .leading, spacing: 8) {
            InstrumentSectionHeader(scope: scope)
            card
        }
        .padding(.horizontal, 16)
        .modifier(CompeteEntrance(index: entranceIndex))
        // `.contain` keeps the rows' and the View Full Leaderboard CTA's identifiers reachable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.compete.leaderboard-card.\(scope.id)")
    }

    /// The full board View Full Leaderboard opens: the instrument's, or the combo's
    /// (web `navigateToLeaderboards(scope)`).
    var fullBoardRoute: AppRoute {
        switch scope {
        case let .instrument(instrument):
            .fullRankings(instrument: instrument, rankBy: CompetePreviewSpotlight.metric.rawValue)
        case let .combo(combo):
            .fullComboRankings(combo: combo, rankBy: CompetePreviewSpotlight.metric.rawValue)
        }
    }

    /// The one leaderboard design (operator batch 7.4): the top five and the player's own
    /// row (the player's purple) as entries of one group card, like the Rivals cards
    /// (issue #381), ending with the shared purple "View Full Leaderboard" button inside
    /// the card (batch 7.6, #382).
    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .loading:
                // Not reached: the page gate shows one spinner until every read settles.
                EmptyView()
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "compete.\(scope.id)", retry: retry)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .festivalCard(cornerRadius: 12)
            case let .loaded(payload) where payload.rankings.entries.isEmpty:
                FestivalFootnote("No ranked \(scope.label) players yet.")
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .festivalCard(cornerRadius: 12)
            case let .loaded(payload):
                FestivalGlassSection(rows: .flush(separatorInset: RankingRowLayout.horizontalPadding)) {
                    ForEach(payload.rankings.entries) { entry in
                        AccountRankingRow(
                            entry: entry, metric: .totalscore,
                            isSelected: isSelected(entry.accountId), cardSurface: true
                        )
                    }
                    if let spotlight {
                        spotlightRow(spotlight)
                    }
                } action: {
                    // Ends the card inside it, after the player's own row (#382).
                    NavigationLink(value: fullBoardRoute) {
                        PurpleActionLabel(title: "View Full Leaderboard")
                    }
                    .festivalRowButtonStyle()
                    .accessibilityLabel(PurpleActionName.spoken("View Full Leaderboard", card: scope.label))
                    .accessibilityIdentifier("fst.compete.leaderboard-card.\(scope.id).view-all")
                }
                // One rank, songs and score width for the card and the player's own row
                // (issue #37, web `computeRankWidth` with `playerEntry`); on a narrow
                // card (portrait iPhone) every row drops songs played/total when it
                // would truncate a name (issue #38).
                .leaderboardSectionColumns(
                    .rankings(cardRows(payload), metric: .totalscore),
                    hidingCrowdedSongsFor: cardRows(payload).map {
                        RankingRowName(
                            name: AccountRankingRow.displayName($0), emphasized: isSelected($0.accountId)
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isSelected(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    /// Every row the card draws: the top five, then the player's own row.
    ///
    /// - Parameter payload: The loaded preview.
    /// - Returns: Rows in display order.
    private func cardRows(_ payload: RankingsPayload) -> [AccountRankingEntry] {
        payload.rankings.entries + (spotlight.map { [$0] } ?? [])
    }

    /// The selected player's own row under the top five: the same highlighted row, as a
    /// link to their position on the full board (``CompetePreviewSpotlight``, #370).
    ///
    /// - Parameter entry: The player's row on this scope's board.
    private func spotlightRow(_ entry: AccountRankingEntry) -> some View {
        let rank = entry.rank(for: .totalscore)
        // Plain, as the ranking rows: `ListDetailLink` draws the Mac hover, ring and Return.
        return ListDetailLink(value: CompetePreviewSpotlight.route(for: entry, scope: scope)) {
            AccountRankingRow(
                entry: entry, metric: .totalscore, isSelected: true, cardSurface: true, opensProfile: false
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CompetePreviewSpotlight.action(for: entry).footerLabel(for: .player, rank: rank))
        .accessibilityIdentifier("fst.compete.leaderboard-card.\(scope.id).spotlight")
    }
}

// MARK: - Preview spotlight route

/// Where the selected player's own row under a Compete leaderboard preview goes: the
/// owner-approved Compete variant of leaderboard-row R7 (#370). Like Song Detail's
/// appended row, it opens the instrument's full rankings for the card's metric on the
/// page containing the rank, which then reveals the highlighted row (web `navToPlayer`),
/// instead of the profile the web `CompetePage` links it to. A row with no usable rank
/// opens Statistics, as the full board's pinned footer does.
enum CompetePreviewSpotlight {
    /// Compete's previews rank by total score (web `CompetePage`).
    static let metric = RankingMetric.totalscore

    /// The row's selected-row action.
    ///
    /// - Parameter entry: The player's row, shown apart from the top five.
    /// - Returns: ``SelectedRowAction/jump(page:)`` to their full-board page, or
    ///   ``SelectedRowAction/openProfile`` without a usable rank.
    static func action(for entry: AccountRankingEntry) -> SelectedRowAction {
        SelectedRowAction.preview(
            rank: entry.rank(for: metric), isAppended: true, pageSize: FullRankingsScreen.pageSize
        )
    }

    /// The route the row opens.
    ///
    /// - Parameters:
    ///   - entry: The player's row, shown apart from the top five.
    ///   - instrument: The preview's instrument.
    /// - Returns: Full Rankings on the player's page with their row revealed, or
    ///   Statistics without a usable rank.
    static func route(for entry: AccountRankingEntry, instrument: Instrument) -> AppRoute {
        route(for: entry, scope: .instrument(instrument))
    }

    /// The route the row opens on an instrument's or a combo's preview (#602).
    ///
    /// - Parameters:
    ///   - entry: The player's row, shown apart from the top five.
    ///   - scope: The preview's instrument or combo.
    /// - Returns: The full board (the combo's for a combo) on the player's page with their
    ///   row revealed, or Statistics without a usable rank.
    static func route(for entry: AccountRankingEntry, scope: RankingScope) -> AppRoute {
        switch (action(for: entry), scope) {
        case let (.jump(page), .instrument(instrument)):
            .fullRankings(instrument: instrument, rankBy: metric.rawValue, page: page, focusSelected: true)
        case let (.jump(page), .combo(combo)):
            .fullComboRankings(combo: combo, rankBy: metric.rawValue, page: page, focusSelected: true)
        case (.openProfile, _):
            .statistics
        }
    }
}

// MARK: - Title

/// The Duo dual-source layout keeps an inline title: its primary region doesn't scroll
/// vertically, so a large title would never collapse. Applied outside the page gate, so
/// the title doesn't change size when the page reveals (#354).
private struct CompeteTitleDisplayMode: ViewModifier {
    let dualSource: Bool

    func body(content: Content) -> some View {
        content.festivalTitleDisplayMode(dualSource ? .inline : .automatic)
    }
}

// MARK: - Entrance

/// A Compete card's place in the page's first-load stagger, or no fade without one.
private struct CompeteEntrance: ViewModifier {
    let index: Int?

    func body(content: Content) -> some View {
        if let index {
            content.festivalFadeIn(isLoaded: true, index: index)
        } else {
            content
        }
    }
}
