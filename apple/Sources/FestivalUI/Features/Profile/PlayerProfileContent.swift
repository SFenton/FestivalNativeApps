import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerProfileContent

/// Loading, syncing, error and available states for one player-profile read.
enum PlayerProfilePhase {
    case loading
    case syncing
    case available(PlayerProfilePayload)
    case failed(ServiceIssue)

    /// The phase that may be drawn for `accountId`.
    ///
    /// `task(id:)` only restarts a load *after* SwiftUI has already re-rendered with
    /// the new `accountId`, so a view whose identity survives an account change
    /// (e.g. the Statistics root after a profile switch) would otherwise draw one
    /// frame of the previous account's validated payload under the new identity.
    /// An available payload for any other account is therefore shown as loading.
    ///
    /// - Parameter accountId: Account the view currently represents.
    /// - Returns: `self`, or `.loading` when the payload belongs to another account.
    func shown(for accountId: String) -> PlayerProfilePhase {
        if case let .available(payload) = self,
           payload.profile.accountId.caseInsensitiveCompare(accountId) != .orderedSame {
            return .loading
        }
        return self
    }
}

/// Shared body for the pushed `/player/:accountId` route (`PlayerProfileScreen`) and
/// the Statistics tab root for the selected player (`StatisticsScreen`) — the web
/// renders both from the same `PlayerPage` component (`App.tsx:95-105`).
///
/// Only the keyless, side-effect-free `GET /api/player/{accountId}` compact-score
/// read is used (`FestivalSession.viewPlayer(accountId:)`). Per-instrument global
/// ranks, the percentile table and the rank-history chart all require the
/// player-stats GET, which `.agents/controls/profile-selection.md` documents as
/// **not** unconditionally read-only (it can compute and store missing tiers), so
/// this screen never calls it; those sections are left out rather than faked.
struct PlayerProfileContent: View {
    let session: FestivalSession
    let accountId: String
    let routeDisplayName: String?
    /// True only for the Statistics tab root: it then ends its own `.toolbar` with
    /// `FestivalRootTrailingItems` (bell + avatar) after the Quick Links button,
    /// per `.agents/controls/app-navigation/ios.md`'s toolbar-order rule, and reports
    /// that to `festivalRootChrome` so it does not add a second copy. The pushed
    /// `/player/:accountId` route (`PlayerProfileScreen`) leaves this false: pushed
    /// pages never show that chrome.
    var showsRootTrailingItems: Bool = false

    @State private var phase = PlayerProfilePhase.loading
    @State private var retryRevision = 0
    /// `LoadKey` whose read finished (successfully or as a known "syncing" state); a
    /// reappearance with the same key skips reloading. `PlayerProfileContent` backs
    /// both the Statistics tab root and the pushed `/player/:accountId` route, both
    /// inside a `NavigationStack`: like Leaderboards (Lane W1), `.task(id:)` restarts
    /// on every reappearance (e.g. Back from Player Bands), not only when the id
    /// value actually changes, so an unguarded reload flashed `phase` back to
    /// `.loading` on every pop. A failed load leaves this nil so the next reappearance
    /// (or explicit Retry) tries again.
    @State private var loadedKey: LoadKey?
    @State private var switchPending = false
    @State private var deselectPending = false
    @State private var actionError: String?
    @State private var quickLinks = QuickLinksController()
    @Environment(\.deviceLayout) private var layout
    @Environment(\.isTabAccessoryAvailable) private var accessoryAvailable
    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true

    private struct LoadKey: Hashable {
        let accountId: String
        let retry: Int
        let publicationRevision: Int
    }

    private var loadKey: LoadKey {
        LoadKey(accountId: accountId, retry: retryRevision, publicationRevision: session.publicationRevision)
    }

    /// Whether `phase` reflects a finished read worth remembering in `loadedKey`
    /// (a failure is deliberately excluded, so the next reappearance retries it).
    private var loadFinished: Bool {
        switch phase {
        case .available, .syncing: true
        case .loading, .failed: false
        }
    }

    /// Create the shared player-profile content.
    ///
    /// - Parameters:
    ///   - session: Shared app session (client, selected profile, publication).
    ///   - accountId: Public account being viewed (may or may not be selected).
    ///   - routeDisplayName: Name known before the response arrives, if any.
    ///   - showsRootTrailingItems: Pass `true` only from the Statistics tab root.
    init(
        session: FestivalSession, accountId: String, routeDisplayName: String?,
        showsRootTrailingItems: Bool = false
    ) {
        self.session = session
        self.accountId = accountId
        self.routeDisplayName = routeDisplayName
        self.showsRootTrailingItems = showsRootTrailingItems
    }

    /// Settings-visible solo charts, matching the Songs tab's own policy.
    private var visibleInstruments: [Instrument] {
        let preferences: [(Instrument, Bool)] = [
            (.lead, showLead), (.bass, showBass), (.drums, showDrums),
            (.vocals, showVocals), (.proLead, showProLead), (.proBass, showProBass),
            (.karaoke, showKaraoke), (.proCymbals, showProCymbals),
            (.proDrums, showProDrums),
        ]
        return preferences.compactMap { $0.1 ? $0.0 : nil }
    }

    private var isSelected: Bool { session.selectedPlayer?.accountId == accountId }

    /// Select, Switch or Deselect for the shown account; nil while loading or paused.
    private var identity: ProfileIdentityAction? {
        guard case let .available(payload) = shownPhase else { return nil }
        if isSelected { return .deselect }
        guard let publication = payload.publicationId, publication == session.publicationId
        else { return nil }
        return session.selectedPlayer == nil ? .select : .switchTo
    }

    /// Values the tab accessory displays; re-registers it when any changes.
    private struct IdentityAccessoryToken: Hashable {
        let action: ProfileIdentityAction?
        let name: String
    }

    /// `phase`, never showing another account's payload (see `PlayerProfilePhase.shown(for:)`).
    private var shownPhase: PlayerProfilePhase { phase.shown(for: accountId) }

    private var displayName: String {
        if case let .available(payload) = shownPhase, let name = payload.profile.displayName {
            return name
        }
        return routeDisplayName ?? accountId
    }

    var body: some View {
        content
            .navigationTitle(displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .task(id: loadKey) {
                guard loadedKey != loadKey else { return }
                let key = loadKey
                await load()
                if !Task.isCancelled && loadFinished { loadedKey = key }
            }
            .confirmationDialog(
                "Switch selected profile?", isPresented: $switchPending,
                titleVisibility: .visible
            ) {
                Button("Switch Profile", role: .destructive) { select() }
            } message: {
                Text("Scores and profile-dependent pages will update to \(displayName).")
            }
            .confirmationDialog(
                "Deselect profile?", isPresented: $deselectPending,
                titleVisibility: .visible
            ) {
                Button("Deselect Profile", role: .destructive) { session.deselectPlayer() }
            } message: {
                Text("Scores and profile-only content will be hidden; app Settings stay saved.")
            }
            .festivalTabAccessory(
                token: IdentityAccessoryToken(action: identity, name: displayName),
                isEnabled: identity != nil
            ) {
                if let identity {
                    ProfileIdentityAccessory(name: displayName, action: identity) {
                        perform(identity)
                    }
                }
            }
            .toolbar {
                if let identity {
                    if layout.sectionChrome.isVerticalBar {
                        // iPhone Duo: in the rail, its own group after Back (Lane W1).
                        VerticalBarActionItem(
                            title: identity.title, systemImage: identity.systemImage,
                            identifier: identity.railAccessibilityIdentifier,
                            action: { perform(identity) }
                        )
                    } else if !accessoryAvailable {
                        ProfileIdentityToolbarItem(
                            action: identity, onTabRoot: showsRootTrailingItems, perform: perform
                        )
                    }
                }
                QuickLinksToolbarItem(quickLinks)
                if showsRootTrailingItems {
                    FestivalRootTrailingItems(session: session)
                }
            }
            .preference(key: FestivalRootTrailingProvidedKey.self, value: showsRootTrailingItems)
    }

    @ViewBuilder private var content: some View {
        switch shownPhase {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading Profile")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("fst.player.loading")
        case .syncing:
            ServiceUnavailableView(
                title: "Scores Are Syncing",
                message: "\(displayName)'s public scores are still syncing. Try again shortly.",
                retry: { retryRevision += 1 }
            )
            .accessibilityIdentifier("fst.player.syncing")
        case let .failed(issue):
            ServiceStatusView(issue, title: "Profile Unavailable") { retryRevision += 1 }
            .accessibilityIdentifier("fst.player.error")
        case let .available(payload):
            // iPhone Duo inner display, portrait: overview on top, graphs as swipeable
            // cards below (`PlayerProfileDualSource.swift`).
            DualSourceLayout {
                profileScroll(payload)
            } secondary: {
                PlayerChartsCarousel(
                    session: session, accountId: accountId, payload: payload, instruments: visibleInstruments
                )
            }
        }
    }

    private func profileScroll(_ payload: PlayerProfilePayload) -> some View {
        ScrollView {
            // New content fades in as it loads: sections stagger like the web's
            // `PlayerPage` `useStagger` (`Common/FadeInOnLoad.swift`).
            VStack(alignment: .leading, spacing: 20) {
                header(payload)
                    .festivalFadeIn(isLoaded: true, index: 0)
                overallSection(payload)
                    .festivalFadeIn(isLoaded: true, index: 1)
                if layout.widthClass == .regular {
                    // Two flexible columns on a regular-width window (Duo unfolded,
                    // iPad): each instrument's stats card and charts read as one
                    // dashboard tile instead of stretching full width
                    // (`.agents/design/apple/duo.md`).
                    LazyVGrid(columns: instrumentGridColumns, alignment: .leading, spacing: 20) {
                        ForEach(Array(visibleInstruments.enumerated()), id: \.element) { index, instrument in
                            instrumentTile(payload, instrument: instrument)
                                .festivalFadeIn(isLoaded: true, index: index + 2)
                        }
                    }
                } else {
                    ForEach(Array(visibleInstruments.enumerated()), id: \.element) { index, instrument in
                        VStack(alignment: .leading, spacing: 20) {
                            instrumentSection(payload, instrument: instrument)
                            instrumentCharts(payload, instrument: instrument)
                        }
                        .festivalFadeIn(isLoaded: true, index: index + 2)
                    }
                }
                bandsLink
                    .festivalFadeIn(isLoaded: true, index: visibleInstruments.count + 2)
            }
            .padding(16)
        }
        .quickLinks(quickLinks, title: "Quick Links")
        .accessibilityIdentifier("fst.player.available")
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ payload: PlayerProfilePayload) -> some View {
        FestivalGlassSection {
            HStack(spacing: 12) {
                ProfileAvatar(name: displayName, size: 44)
                // Name only, like the web's PlayerPage: selection state shows solely
                // through the Select/Switch/Deselect action (operator, 2026-09-28).
                Text(displayName)
                    .font(.title3.bold())
                    .foregroundStyle(BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.player.name")
                Spacer(minLength: 0)
            }
            identityPause(payload)
            if let actionError {
                Text(actionError)
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.gold)
                    .accessibilityIdentifier("fst.player.action-error")
            }
        }
    }

    /// Why selection is paused, when it is. The Select/Switch/Deselect action itself
    /// lives in the tab accessory or toolbar (`ProfileIdentityAccessory.swift`).
    ///
    /// - Parameter payload: Current validated read backing the action.
    @ViewBuilder
    private func identityPause(_ payload: PlayerProfilePayload) -> some View {
        if isSelected {
            EmptyView()
        } else if payload.publicationId == nil {
            Text("These scores have no verified publication. Selection is paused.")
                .font(.footnote)
                .foregroundStyle(BrandTokens.gold)
                .accessibilityIdentifier("fst.player.unverified")
        } else if payload.publicationId != session.publicationId {
            Text("Published scores changed. Reload this page before selecting.")
                .font(.footnote)
                .foregroundStyle(BrandTokens.gold)
                .accessibilityIdentifier("fst.player.preview-changed")
        }
    }

    /// Carry out an identity action; Switch and Deselect confirm first.
    ///
    /// - Parameter action: Action chosen in the accessory or toolbar.
    private func perform(_ action: ProfileIdentityAction) {
        switch action {
        case .select: select()
        case .switchTo: switchPending = true
        case .deselect: deselectPending = true
        }
    }

    /// Promote the current viewed, response-proven read to the selected profile.
    private func select() {
        guard case let .available(payload) = shownPhase else { return }
        let result = PlayerSearchResult(accountId: payload.profile.accountId, displayName: displayName)
        do {
            try session.selectPlayer(result, from: payload)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: Overview

    @ViewBuilder
    private func overallSection(_ payload: PlayerProfilePayload) -> some View {
        let stats = payload.profile.overallStats(visibleInstruments: Set(visibleInstruments))
        FestivalGlassSection("Overview") {
            statGrid(items: [
                ("Songs Played", "\(stats.songsPlayed)", nil),
                (
                    "Full Combos",
                    stats.fullComboCount == 0 ? "0" : "\(stats.fullComboCount) (\(percentText(stats.fullComboPercent))%)",
                    nil
                ),
                ("Gold Stars", "\(stats.goldStarCount)", BrandTokens.gold),
                ("Avg Accuracy", accuracyText(stats.averageAccuracy), nil),
                ("Best Rank", stats.bestRank.map { "#\($0)" } ?? "—", nil),
            ])
        }
        .accessibilityIdentifier("fst.player.overview")
        .quickLinkSection(id: "global", title: "Global Statistics", symbol: "chart.bar.fill")
    }

    // MARK: Per-instrument

    @ViewBuilder
    private func instrumentSection(_ payload: PlayerProfilePayload, instrument: Instrument) -> some View {
        let stats = payload.profile.instrumentStats(instrument)
        FestivalGlassSection {
            HStack(spacing: 8) {
                InstrumentIcon(instrument, size: 22)
                Text(instrument.label)
                    .font(.headline)
                    .foregroundStyle(BrandTokens.textPrimary)
            }
            if stats.songsPlayed == 0 {
                FestivalFootnote("No \(instrument.label) scores recorded yet.")
                    .accessibilityIdentifier("fst.player.instrument-empty.\(instrument.rawValue)")
            } else {
                statGrid(items: [
                    ("Songs Played", "\(stats.songsPlayed)", nil),
                    (
                        "Full Combos",
                        stats.fullComboCount == 0 ? "0" : "\(stats.fullComboCount) (\(percentText(stats.fullComboPercent))%)",
                        stats.fullComboCount > 0 ? BrandTokens.gold : nil
                    ),
                    ("Gold Stars", "\(stats.goldStarCount)", BrandTokens.gold),
                    ("5 Stars", "\(stats.fiveStarCount)", nil),
                    ("Avg Accuracy", accuracyText(stats.averageAccuracy), nil),
                    ("Best Rank", stats.bestRank.map { "#\($0)" } ?? "—", nil),
                ])
                InstrumentGlobalRankView(session: session, accountId: accountId, instrument: instrument)
            }
        }
        .accessibilityIdentifier("fst.player.instrument.\(instrument.rawValue)")
        .quickLinkSection(QuickLinkSection(
            id: "instrument:\(instrument.rawValue)", title: instrument.label, icon: .instrument(instrument)
        ))
    }

    // MARK: Regular-width grid

    private var instrumentGridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]
    }

    /// One dashboard tile: an instrument's stats card followed by its charts,
    /// grouped so the regular-width grid places both in the same column together.
    ///
    /// - Parameters:
    ///   - payload: Current validated profile read.
    ///   - instrument: Settings-visible solo chart.
    @ViewBuilder
    private func instrumentTile(_ payload: PlayerProfilePayload, instrument: Instrument) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            instrumentSection(payload, instrument: instrument)
            instrumentCharts(payload, instrument: instrument)
        }
    }

    // MARK: Graphs

    /// The instrument's rank-history and percentile graphs, as separate glass cards
    /// after its stats card (`PlayerProfileCharts.swift`); none for an unplayed chart,
    /// matching the web's empty-instrument block.
    ///
    /// - Parameters:
    ///   - payload: Current validated profile read.
    ///   - instrument: Settings-visible solo chart.
    @ViewBuilder
    private func instrumentCharts(_ payload: PlayerProfilePayload, instrument: Instrument) -> some View {
        // Split around the Duo fold, the graphs live in the bottom region instead.
        if !DualSourcePolicy.isActive(layout), payload.profile.instrumentStats(instrument).songsPlayed > 0 {
            PlayerRankHistoryCard(session: session, accountId: accountId, instrument: instrument)
            PlayerPercentileChartCard(
                buckets: payload.profile.percentileBuckets(instrument), instrument: instrument
            )
        }
    }

    // MARK: Bands

    private var bandsLink: some View {
        NavigationLink(
            value: AppRoute.playerBands(accountId: accountId, displayName: routeDisplayName ?? displayName)
        ) {
            HStack {
                Image(systemName: "person.3")
                    .accessibilityHidden(true)
                Text("View \(displayName)'s Bands")
                    .foregroundStyle(BrandTokens.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(FestivalText.deemphasized)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("fst.player.bands-link")
        .quickLinkSection(id: "bands", title: "Bands", symbol: "person.3.fill")
    }

    // MARK: Formatting

    /// One decimal only when the percent is not a whole number, matching `ScoreFormatting`.
    private func percentText(_ value: Double) -> String {
        let fractionDigits = value == value.rounded() ? 0 : 1
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// `PlayerScore.accuracy` already decodes into the same ten-thousandths-of-a-percent
    /// scale `ScoreFormatting.accuracy(_:)` expects (compact wire `acc` multiplied by
    /// 1,000; e.g. wire `979` becomes `979_000`, i.e. 97.9%) — no further rescale needed.
    private func accuracyText(_ playerProfileAccuracy: Double?) -> String {
        guard let playerProfileAccuracy else { return "—" }
        return "\(ScoreFormatting.accuracy(playerProfileAccuracy))%"
    }

    // MARK: Load

    /// Read the public profile without selecting or persisting it.
    private func load() async {
        phase = .loading
        do {
            let payload = try await session.viewPlayer(accountId: accountId)
            try Task.checkCancellation()
            phase = payload.state == .syncing ? .syncing : .available(payload)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(ServiceIssue(error))
        }
    }
}

// MARK: - InstrumentGlobalRankView

/// One instrument's global-rankings-board read, independent of the profile load
/// above it. Loading, unranked and error states; success shows Total Score Rank
/// (the web's un-experimental `DEFAULT_METRICS`), its rating and a rank-derived
/// percentile — see `.agents/pages/player-profile/ios.md` for why this reads
/// `GET /api/rankings/{instrument}/{accountId}` and never player-stats.
private enum InstrumentRankPhase {
    case loading
    case unranked
    case available(PlayerInstrumentRanking)
    case failed(String)
}

private struct InstrumentGlobalRankView: View {
    let session: FestivalSession
    let accountId: String
    let instrument: Instrument

    @State private var phase = InstrumentRankPhase.loading
    @State private var retryRevision = 0
    /// See `PlayerProfileContent.loadedKey`: this per-instrument card sits inside the
    /// same reappearing `NavigationStack` root, so it needs the same reappear guard.
    @State private var loadedKey: LoadKey?

    private struct LoadKey: Hashable {
        let accountId: String
        let instrument: Instrument
        let retry: Int
        let publicationRevision: Int
    }

    private var loadKey: LoadKey {
        LoadKey(
            accountId: accountId, instrument: instrument, retry: retryRevision,
            publicationRevision: session.publicationRevision
        )
    }

    private var loadFinished: Bool {
        switch phase {
        case .unranked, .available: true
        case .loading, .failed: false
        }
    }

    var body: some View {
        content
            .task(id: loadKey) {
                guard loadedKey != loadKey else { return }
                let key = loadKey
                await load()
                if !Task.isCancelled && loadFinished { loadedKey = key }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading \(instrument.label) global rank")
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("fst.player.global-rank.\(instrument.rawValue).loading")
        case .unranked:
            FestivalFootnote("Not yet ranked globally on \(instrument.label).")
                .accessibilityIdentifier("fst.player.global-rank.\(instrument.rawValue).unranked")
        case let .failed(message):
            HStack(spacing: 8) {
                Text("Global rank unavailable: \(message)")
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
                Button("Retry") { retryRevision += 1 }
                    .font(.caption.weight(.semibold))
            }
            .accessibilityIdentifier("fst.player.global-rank.\(instrument.rawValue).error")
        case let .available(ranking):
            statGrid(items: [
                ("Global Rank", "#\(ranking.entry.rank(for: .totalscore).formatted())", nil),
                (
                    "Total Score",
                    RankingFormatting.wholeNumber(ranking.entry.ratingValue(for: .totalscore)), nil
                ),
                percentileTile(ranking),
            ])
            .festivalFadeIn(isLoaded: true)
            .accessibilityIdentifier("fst.player.global-rank.\(instrument.rawValue).available")
        }
    }

    /// "Top N%" derived from rank/field-size, since Total Score has no native
    /// Bayesian percentile on the wire (only Adjusted/Weighted do).
    ///
    /// - Parameter ranking: Current validated single-account ranking row.
    /// - Returns: A stat-grid item; gold-tinted for a top-5% placement.
    private func percentileTile(_ ranking: PlayerInstrumentRanking) -> (label: String, value: String, tint: Color?) {
        guard let fraction = ranking.percentile(for: .totalscore) else {
            return ("Percentile", "—", nil)
        }
        let isTopFive = fraction * 100 <= 5
        return ("Percentile", RankingFormatting.percentile(fraction), isTopFive ? BrandTokens.gold : nil)
    }

    /// Read the pure per-instrument rankings-board fallback, never player-stats.
    private func load() async {
        phase = .loading
        do {
            let payload = try await session.playerInstrumentRanking(
                instrument: instrument, accountId: accountId
            )
            try Task.checkCancellation()
            switch payload.state {
            case .available:
                guard let ranking = payload.ranking else {
                    phase = .unranked
                    return
                }
                phase = .available(ranking)
            case .unranked:
                phase = .unranked
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

/// A row of small, flat (non-glass) value/label tiles inside one glass section.
///
/// Kept flat per `.agents/design/apple/liquid-glass.md` ("never glass-on-glass").
private struct StatTile: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let tint: Color?
}

/// Lay out stat tiles as an adaptive grid, matching the web's `StatBox` grid.
private func statGrid(items: [(label: String, value: String, tint: Color?)]) -> some View {
    let tiles = items.map { StatTile(label: $0.label, value: $0.value, tint: $0.tint) }
    return LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8
    ) {
        ForEach(tiles) { tile in
            VStack(spacing: 2) {
                Text(tile.value)
                    .font(.title3.bold())
                    .foregroundStyle(tile.tint ?? BrandTokens.accentBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tile.label)
                    .font(.caption2)
                    .foregroundStyle(FestivalText.primary)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}
