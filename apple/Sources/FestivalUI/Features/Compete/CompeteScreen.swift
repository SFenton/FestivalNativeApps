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
/// (reusing this lane's own `RivalInstrumentSongSection`). No player selected →
/// `RivalsChooseProfileState`. See `.agents/pages/compete/ios.md`.
struct CompeteScreen: View {
    let session: FestivalSession
    @State private var quickLinks = QuickLinksController()
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

    @ViewBuilder private var hub: some View {
        // iPhone Duo inner display, portrait: leaderboards and rivals become two
        // swipeable sources stacked around the fold (`CompeteDualSource.swift`).
        DualSourceLayout {
            if DualSourcePolicy.isActive(layout) {
                CompeteLeaderboardsCarousel(session: session, instruments: visible.instruments)
            } else {
                stackedHub
            }
        } secondary: {
            CompeteRivalsCarousel(session: session, instruments: visible.instruments)
        }
        // Every section below loads for `session.selectedPlayer` but keys its
        // `task(id:)` only on instrument/scope; this hub survives a profile switch
        // (tab root, or pushed on a stack the switch does not reset), so key the
        // sections' state by the selected account or they keep the old account's
        // rivals (`.agents/platforms/apple/architecture.md`, "Per-entity screens").
        .id(session.selectedPlayer?.accountId)
    }

    private var stackedHub: some View {
        ScrollView {
            if layout.widthClass == .regular && !DualSourcePolicy.isActive(layout) {
                // Regular-width columns (Mac, iPad): Leaderboards beside Rivals, the two
                // halves of Compete side by side instead of one very long column.
                HStack(alignment: .top, spacing: 8) {
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
        .quickLinks(quickLinks, title: "Quick Links")
    }

    // MARK: Leaderboards

    /// Like the web's `CompetePage`, there is no Leaderboards overview link here (#36):
    /// each instrument's preview links to its own full leaderboard, and the overview
    /// stays in the drawer.
    private var leaderboardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader("Leaderboards")
                .padding(.horizontal, 16)
            if visible.instruments.isEmpty {
                FestivalFootnote("Enable at least one instrument in Settings to see leaderboards.")
                    .padding(.horizontal, 16)
            } else {
                ForEach(visible.instruments) { instrument in
                    CompeteInstrumentLeaderboardSection(session: session, instrument: instrument)
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
            if visible.instruments.isEmpty {
                FestivalFootnote("Enable at least one instrument in Settings to see rivals.")
                    .padding(.horizontal, 16)
            } else {
                ForEach(visible.instruments) { instrument in
                    RivalInstrumentSongSection(
                        session: session, instrument: instrument, registersQuickLink: false,
                        emptyMessage: "No rivals found for \(instrument.label) yet."
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
/// rows match `LeaderboardsScreen`'s own overview cards. While loading it shows a
/// system spinner card, like the Rivals sections below it.
struct CompeteInstrumentLeaderboardSection: View {
    let session: FestivalSession
    let instrument: Instrument
    @State private var state: RankLoadState<RankingsPayload> = .loading
    /// `.task(id:)` restarts whenever Compete reappears (Back from View Full
    /// Leaderboard), so remember the key that loaded: reloading flashed the rows to a
    /// shorter spinner card and re-faded them, making the page jump (#39).
    @State private var gate = ReappearanceLoadGate<CompeteSectionLoadKey>()

    private let previewCount = 5

    private var loadKey: CompeteSectionLoadKey {
        CompeteSectionLoadKey(instrument: instrument, session: session)
    }

    var body: some View {
        // Instrument header above the card, never inside it (operator rule).
        VStack(alignment: .leading, spacing: 8) {
            InstrumentSectionHeader(instrument)
            card
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("fst.compete.leaderboard-card.\(instrument.rawValue)")
        .task(id: loadKey) {
            guard gate.needsLoad(for: loadKey) else { return }
            await load()
        }
    }

    /// The one leaderboard design (operator batch 7.4): no card around the rows; each
    /// row its own material card (the player's purple), then the shared purple "View Full
    /// Leaderboard" button (batch 7.6).
    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .loading:
                // A system spinner, not `RankingsSkeletonRows`: the redacted bars read
                // as content, so the first screen showed no loading indicator (#35).
                // Same place as the Rivals sections' spinners and this card's own
                // empty/error states.
                FestivalLoadingView(accessibilityLabel: "Loading \(instrument.label) leaderboard")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .festivalCard(cornerRadius: 12)
                    .accessibilityIdentifier("fst.compete.leaderboard-card.\(instrument.rawValue).loading")
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "compete.\(instrument.rawValue)") { Task { await load() } }
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
                .festivalFadeIn(isLoaded: true)
                NavigationLink(
                    value: AppRoute.fullRankings(instrument: instrument, rankBy: "totalscore")
                ) {
                    PurpleActionLabel(title: "View Full Leaderboard")
                }
                .festivalRowButtonStyle()
                .accessibilityIdentifier("fst.compete.leaderboard-card.\(instrument.rawValue).view-all")
                .festivalFadeIn(isLoaded: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isSelected(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    @MainActor
    private func load() async {
        let key = loadKey
        state = .loading
        do {
            state = .loaded(try await session.rankings(
                instrument: instrument, rankBy: .totalscore, page: 1, pageSize: previewCount
            ))
            gate.markLoaded(key)
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }
}

// MARK: - Section load key

/// What a Compete (or Rivals) per-instrument section's read depends on: a change to
/// any part reloads it, while a plain reappearance keeps the loaded rows
/// (``ReappearanceLoadGate``).
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
