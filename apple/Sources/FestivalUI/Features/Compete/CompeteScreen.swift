import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - CompeteScreen

/// `/compete` — phone hub combining Leaderboards and Rivals; this is the phone
/// tab shown once a player is selected (see `FestivalRootView`).
///
/// Ports the web's `CompetePage`: a Leaderboards section (live Top-5 preview per
/// Settings-visible instrument, reusing Lane L's `AccountRankingRow`/`RankLoadState`
/// from `Features/Leaderboards/RankingsSupport.swift`) and a Rivals section
/// (reusing `RivalInstrumentSongCard`). Like the web, the whole page loads behind one
/// spinner, then its headers and cards fade in on one stagger (``CompeteHubModel``,
/// load-transition R1, #354). No player selected → `RivalsChooseProfileState`. See
/// `.agents/pages/compete/ios.md`.
struct CompeteScreen: View {
    let session: FestivalSession
    @State private var quickLinks = QuickLinksController()
    @State private var model = CompeteHubModel()
    /// Leaderboard cards the Duo top carousel shows side by side (its reading order).
    @State private var leaderboardColumns = 1
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
                    session: session, instruments: visible.instruments, model: model, retry: retryFailedReads
                )
            } else {
                stackedHub
            }
        } secondary: {
            CompeteRivalsCarousel(
                instruments: visible.instruments, model: model, leaderboardColumns: leaderboardColumns,
                retry: retryFailedReads
            )
        }
        // The Duo panes' one first-load window, rushed by a swipe in either carousel
        // (load-transition R5). The stacked hub installs its own inside its scroll view.
        .festivalNestedFadeInScope()
        // The carousels span the page's width; the Rivals pane follows the leaderboard
        // cards on screen in reading order. The secondary region only appears once the
        // layout has measured itself, so this is known before the Rivals pane fades.
        .onGeometryChange(for: Int.self) { proxy in
            CarouselPaging.columns(
                width: proxy.size.width.rounded(), minimumCardWidth: CompeteDualSourceEntrance.minimumCardWidth
            )
        } action: { columns in
            leaderboardColumns = columns
        }
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

    /// Stagger position of the Leaderboards header; its cards follow in instrument order.
    private static let leaderboardsHeaderIndex = 0

    /// Stagger position of the Rivals header (web `useStagger().next()` reading order:
    /// the Leaderboards header, each leaderboard card, then the Rivals header and cards).
    private var rivalsHeaderIndex: Int { visible.instruments.count + 1 }

    // MARK: Leaderboards

    /// Like the web's `CompetePage`, there is no Leaderboards overview link here (#36):
    /// each instrument's preview links to its own full leaderboard, and the overview
    /// stays in the drawer.
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
                ForEach(Array(visible.instruments.enumerated()), id: \.element) { offset, instrument in
                    CompeteInstrumentLeaderboardSection(
                        session: session, instrument: instrument, state: model.boards[instrument] ?? .loading,
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
                ForEach(Array(visible.instruments.enumerated()), id: \.element) { offset, instrument in
                    RivalInstrumentSongCard(
                        instrument: instrument, state: model.rivals[instrument] ?? .loading,
                        registersQuickLink: false,
                        emptyMessage: "No rivals found for \(instrument.label) yet.",
                        entranceIndex: rivalsHeaderIndex + 1 + offset, retry: retryFailedReads
                    )
                }
            }
        }
        .quickLinkSection(id: "rivals", title: "Rivals", symbol: "person.2.fill")
    }
}

// MARK: - Per-instrument leaderboard preview

/// One instrument's Top-5 ranking preview, reusing Lane L's `RankLoadState`/
/// `AccountRankingRow` (`Features/Leaderboards/RankingsSupport.swift`) so Compete's
/// rows match `LeaderboardsScreen`'s own overview cards. The page reads it
/// (``CompeteHubModel``) and only builds it once every read settled, so it never shows a
/// spinner of its own (#354).
struct CompeteInstrumentLeaderboardSection: View {
    let session: FestivalSession
    let instrument: Instrument
    let state: RankLoadState<RankingsPayload>
    /// The card's place in the page's first-load stagger.
    var entranceIndex: Int? = nil
    /// Reads the preview again after a failure.
    let retry: () -> Void

    var body: some View {
        // Instrument header above the card, never inside it (operator rule).
        VStack(alignment: .leading, spacing: 8) {
            InstrumentSectionHeader(instrument)
            card
        }
        .padding(.horizontal, 16)
        .modifier(CompeteEntrance(index: entranceIndex))
        // `.contain` keeps the rows' and the View Full Leaderboard CTA's identifiers reachable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.compete.leaderboard-card.\(instrument.rawValue)")
    }

    /// The one leaderboard design (operator batch 7.4): no card around the rows; each
    /// row its own material card (the player's purple), then the shared purple "View Full
    /// Leaderboard" button (batch 7.6).
    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .loading:
                // Not reached: the page gate shows one spinner until every read settles.
                EmptyView()
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "compete.\(instrument.rawValue)", retry: retry)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .festivalCard(cornerRadius: 12)
            case let .loaded(payload) where payload.rankings.entries.isEmpty:
                FestivalFootnote("No ranked \(instrument.label) players yet.")
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .festivalCard(cornerRadius: 12)
            case let .loaded(payload):
                VStack(spacing: 6) {
                    ForEach(payload.rankings.entries) { entry in
                        AccountRankingRow(
                            entry: entry, metric: .totalscore,
                            isSelected: isSelected(entry.accountId), cardSurface: true
                        )
                    }
                }
                // One rank, songs and score width for the card (issue #37); on a
                // narrow card (portrait iPhone) every row drops songs played/total
                // when it would truncate a name (issue #38).
                .leaderboardSectionColumns(
                    .rankings(payload.rankings.entries, metric: .totalscore),
                    hidingCrowdedSongsFor: payload.rankings.entries.map {
                        RankingRowName(
                            name: AccountRankingRow.displayName($0), emphasized: isSelected($0.accountId)
                        )
                    }
                )
                NavigationLink(
                    value: AppRoute.fullRankings(instrument: instrument, rankBy: "totalscore")
                ) {
                    PurpleActionLabel(title: "View Full Leaderboard")
                }
                .festivalRowButtonStyle()
                .accessibilityIdentifier("fst.compete.leaderboard-card.\(instrument.rawValue).view-all")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isSelected(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }
}

// MARK: - Title

/// The Duo dual-source layout keeps an inline title: its primary region doesn't scroll
/// vertically, so a large title would never collapse. Applied outside the page gate, so
/// the title doesn't change size when the page reveals (#354).
private struct CompeteTitleDisplayMode: ViewModifier {
    let dualSource: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbarTitleDisplayMode(dualSource ? .inline : .automatic)
        #else
        content
        #endif
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

// MARK: - Section load key

/// What a Rivals hub per-instrument section's read depends on: a change to any part
/// reloads it, while a plain reappearance keeps the loaded rows (``ReappearanceLoadGate``).
/// Compete keys its whole page with ``CompetePageLoadKey`` instead.
struct CompeteSectionLoadKey: Hashable, Sendable {
    let instrument: Instrument
    let accountId: String?
    let publicationRevision: Int

    /// Build the key from the section's instrument and the session's current state.
    ///
    /// - Parameters:
    ///   - instrument: The section's instrument.
    ///   - session: Shared session; its selected account and publication revision.
    @MainActor
    init(instrument: Instrument, session: FestivalSession) {
        self.instrument = instrument
        accountId = session.selectedPlayer?.accountId
        publicationRevision = session.publicationRevision
    }
}
