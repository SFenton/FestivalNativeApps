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

/// Why Select/Switch is paused for a viewed player, shown above the page content.
enum PlayerProfileIdentityNotice: Equatable {
    /// The read carried no verified publication header.
    case unverified
    /// The read's publication differs from the session's current one.
    case publicationChanged

    /// The notice to show for a read, if any.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the shown account is the selected player.
    ///   - payloadPublicationId: Publication proven by the profile read, if any.
    ///   - sessionPublicationId: Publication the session currently observes.
    /// - Returns: The pause reason, or nil when selection is not paused (or the
    ///   player is already selected).
    static func notice(
        isSelected: Bool, payloadPublicationId: Int?, sessionPublicationId: Int?
    ) -> PlayerProfileIdentityNotice? {
        if isSelected { return nil }
        guard let payloadPublicationId else { return .unverified }
        return payloadPublicationId == sessionPublicationId ? nil : .publicationChanged
    }

    /// Readable explanation of the pause.
    var message: String {
        switch self {
        case .unverified: "These scores have no verified publication. Selection is paused."
        case .publicationChanged: "Published scores changed. Reload this page before selecting."
        }
    }

    /// UI-test identifier of the notice text.
    var accessibilityIdentifier: String {
        switch self {
        case .unverified: "fst.player.unverified"
        case .publicationChanged: "fst.player.preview-changed"
        }
    }
}

/// Shared body for the pushed `/player/:accountId` route (`PlayerProfileScreen`) and
/// the Statistics tab root for the selected player (`StatisticsScreen`) — the web
/// renders both from the same `PlayerPage` component (`App.tsx:95-105`).
///
/// Reads only pure, keyless GETs: the compact scores (`GET /api/player/{accountId}`),
/// then, in parallel for every played visible instrument, its rankings-board row and
/// 30-day rank history. Never the player-stats GET, which
/// `.agents/controls/profile-selection/spec.md` documents as **not** unconditionally
/// read-only; its stats are computed client-side.
///
/// Like the web `PlayerPage`, nothing but a spinner shows until those reads settle;
/// then the page fades in and its cards stagger (operator batch 6.41), so ranks and
/// charts never pop into a half-drawn page. Layout follows the web's flat item list:
/// every stat is its own card; per instrument the header, the Rank History card, the
/// stat cards and the Percentiles table card follow each other (batch 6.18/6.26).
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
    /// Stat link waiting on the Switch confirmation (web `withProfileSwitch`).
    @State private var pendingLink: PlayerStatLink?
    @State private var deselectPending = false
    @State private var actionError: String?
    @State private var quickLinks = QuickLinksController()
    /// Each played instrument's ranking read, finished before the page appears.
    @State private var rankPreloads: [Instrument: InstrumentStatsCard.Phase] = [:]
    /// Each played instrument's rank-history read, finished before the page appears.
    @State private var historyPreloads: [Instrument: PlayerRankHistoryCard.Phase] = [:]
    @Environment(\.deviceLayout) private var layout
    @Environment(\.playerStatNavigator) private var navigator
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

    /// The identity action this page will offer, known from the session alone, so the
    /// toolbar has its final shape from the first frame of a push. Until the read
    /// proves it (``identity``), the button shows disabled: inserting it after the load
    /// re-laid out the navigation bar mid-push (Liquid Glass morphs every item).
    private var plannedIdentity: ProfileIdentityAction {
        if isSelected { return .deselect }
        return session.selectedPlayer == nil ? .select : .switchTo
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
            .festivalNavigationTitle(displayName)
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
                Button("Switch Profile", role: .destructive) {
                    let link = pendingLink
                    pendingLink = nil
                    if select(), let link { navigate(link) }
                }
                Button("Cancel", role: .cancel) { pendingLink = nil }
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
            .toolbar {
                // Deselect lives in the drawer, not on the player page (operator batch
                // 7.10); the page offers only Select / Switch.
                if let identity, identity != .deselect {
                    if layout.sectionChrome.isVerticalBar {
                        // iPhone Duo: in the rail, its own group after Back (Lane W1).
                        VerticalBarActionItem(
                            title: identity.title, systemImage: identity.systemImage,
                            identifier: identity.railAccessibilityIdentifier,
                            action: { perform(identity) }
                        )
                    } else {
                        // Its own header button (operator: not part of a bottom bar).
                        ProfileIdentityToolbarItem(
                            action: identity, perform: perform
                        )
                    }
                } else if !layout.sectionChrome.isVerticalBar, showsIdentityPlaceholder, plannedIdentity != .deselect {
                    // Same button, disabled, while the read is in flight or paused.
                    ProfileIdentityToolbarItem(
                        action: plannedIdentity,
                        isEnabled: false, perform: perform
                    )
                }
                QuickLinksToolbarItem(quickLinks)
                if showsRootTrailingItems {
                    FestivalRootTrailingItems(session: session)
                }
            }
            .preference(key: FestivalRootTrailingProvidedKey.self, value: showsRootTrailingItems)
    }

    /// Whether to hold the identity button's place (disabled) instead of hiding it:
    /// while loading, and while selection is paused. A failed or syncing read offers no
    /// action at all.
    private var showsIdentityPlaceholder: Bool {
        switch shownPhase {
        case .loading, .available: true
        case .syncing, .failed: false
        }
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
        let notice = identityNotice(payload)
        // The notices card, when shown, takes the first stagger slot; everything else
        // follows it, so the first visible item always fades in first.
        let first = (notice != nil || actionError != nil) ? 1 : 0
        return ScrollView {
            // New content fades in as it loads: sections stagger like the web's
            // `PlayerPage` `useStagger` (`Common/FadeInOnLoad.swift`). No avatar/name
            // card: the large navigation title already names the player (issue #97).
            VStack(alignment: .leading, spacing: 20) {
                if first == 1 {
                    identityNotices(notice)
                        .festivalFadeIn(isLoaded: true, index: 0)
                }
                overallSection(payload)
                    .festivalFadeIn(isLoaded: true, index: first)
                FestivalSectionHeader(
                    "Instrument Statistics",
                    subtitle: "A quick look at \(displayName)'s overall Festival statistics per instrument."
                )
                .padding(.horizontal, 4)
                .festivalFadeIn(isLoaded: true, index: first + 1)
                if layout.widthClass == .regular {
                    // Two flexible columns on a regular-width window (Duo unfolded,
                    // iPad): each instrument's stats card and charts read as one
                    // dashboard tile instead of stretching full width
                    // (`.agents/design/apple/duo.md`).
                    LazyVGrid(columns: instrumentGridColumns, alignment: .leading, spacing: 20) {
                        ForEach(Array(visibleInstruments.enumerated()), id: \.element) { index, instrument in
                            instrumentTile(payload, instrument: instrument)
                                .festivalFadeIn(isLoaded: true, index: first + 2 + index)
                        }
                    }
                } else {
                    ForEach(Array(visibleInstruments.enumerated()), id: \.element) { index, instrument in
                        instrumentTile(payload, instrument: instrument)
                            .festivalFadeIn(isLoaded: true, index: first + 2 + index)
                    }
                }
                bandsLink
                    .festivalFadeIn(isLoaded: true, index: first + 2 + visibleInstruments.count)
            }
            .padding(16)
            .festivalFadeInScope()
        }
        // On the scroll view itself: after `.quickLinks` it would land on the
        // `ScrollViewReader` wrapper, which UI tests cannot find.
        .accessibilityIdentifier("fst.player.available")
        .debugPageScrollStress()
        .quickLinks(quickLinks, title: "Quick Links")
    }

    // MARK: Identity notices

    /// Why selection is paused for `payload`, if it is.
    ///
    /// - Parameter payload: Current validated read backing the action.
    /// - Returns: The pause reason, or nil.
    private func identityNotice(_ payload: PlayerProfilePayload) -> PlayerProfileIdentityNotice? {
        PlayerProfileIdentityNotice.notice(
            isSelected: isSelected, payloadPublicationId: payload.publicationId,
            sessionPublicationId: session.publicationId
        )
    }

    /// Selection-pause notice and Select/Switch error, in one card shown only while
    /// either applies. The page title already names the player, so there is no
    /// avatar or name here (issue #97). The action itself is a toolbar item
    /// (`ProfileIdentityToolbarItem` in `ProfileIdentityAction.swift`).
    ///
    /// - Parameter notice: Current pause reason, if any.
    private func identityNotices(_ notice: PlayerProfileIdentityNotice?) -> some View {
        FestivalGlassSection {
            if let notice {
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(notice.accessibilityIdentifier)
            }
            if let actionError {
                Text(actionError)
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("fst.player.action-error")
            }
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
    ///
    /// - Returns: Whether the player is now selected.
    @discardableResult
    private func select() -> Bool {
        guard case let .available(payload) = shownPhase else { return false }
        let result = PlayerSearchResult(accountId: payload.profile.accountId, displayName: displayName)
        do {
            try session.selectPlayer(result, from: payload)
            actionError = nil
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: Stat links

    /// A tile's link as drawn: nil (a plain tile) without the root navigator, or for a
    /// Songs filter while selection is paused (it would filter someone else's scores).
    ///
    /// - Parameter link: The web's target for the tile.
    /// - Returns: The link to attach, or nil.
    private func tileLink(_ link: PlayerStatLink?) -> PlayerStatLink? {
        guard let link, navigator != nil else { return nil }
        if link.requiresSelection, !isSelected, identity == nil { return nil }
        return link
    }

    /// Follow a tapped tile, selecting a viewed player first (web `withProfileSwitch`):
    /// Select immediately, Switch after confirmation, and while selection is paused
    /// open only links that do not need it.
    ///
    /// - Parameter link: The tapped tile's link.
    private func open(_ link: PlayerStatLink) {
        if isSelected {
            navigate(link)
            return
        }
        switch identity {
        case .select:
            if select() { navigate(link) }
        case .switchTo:
            pendingLink = link
            switchPending = true
        case .deselect:
            navigate(link)
        case nil:
            if !link.requiresSelection { navigate(link) }
        }
    }

    /// Carry out a link through the root navigator.
    ///
    /// - Parameter link: Link to follow.
    private func navigate(_ link: PlayerStatLink) {
        guard let navigator else { return }
        switch link {
        case let .songs(preset):
            navigator.showSongs(preset)
        case let .fullRankings(instrument, rankBy):
            navigator.push(.fullRankings(instrument: instrument, rankBy: rankBy))
        case let .songDetail(songId, _):
            // `AppRoute.songDetail` carries a full `Song`; the profile only has its id, so
            // resolve it from the (cached) catalogue first. A catalogue failure leaves
            // the page where it is rather than opening an empty detail.
            Task { @MainActor in
                guard let payload = try? await session.catalog(),
                      let song = payload.catalog.songs.first(where: { $0.songId == songId })
                else { return }
                navigator.push(.songDetail(song))
            }
        }
    }

    // MARK: Overview

    @ViewBuilder
    private func overallSection(_ payload: PlayerProfilePayload) -> some View {
        let visible = Set(visibleInstruments)
        let stats = payload.profile.overallStats(visibleInstruments: visible)
        // Web `buildOverallSummaryItems`: every stat its own card (no card around the
        // grid). Songs Played and Full Combos filter Songs, Best Rank opens its song;
        // Gold Stars and Avg Accuracy are plain.
        VStack(alignment: .leading, spacing: 8) {
            FestivalSectionHeader("Global Statistics")
                .padding(.horizontal, 4)
            PlayerStatGrid(tiles: [
                StatTile(
                    id: "songs-played", label: "Songs Played", value: stats.songsPlayed.formatted(),
                    link: tileLink(PlayerStatLinks.overallSongsPlayed(visible: visible))
                ),
                StatTile(
                    id: "full-combos", label: "Full Combos",
                    value: fullComboText(count: stats.fullComboCount, percent: stats.fullComboPercent),
                    tint: stats.fullComboPercent >= 100 ? BrandTokens.gold : nil,
                    link: tileLink(PlayerStatLinks.overallFullCombos(visible: visible))
                ),
                StatTile(
                    id: "gold-stars", label: "Gold Stars", value: stats.goldStarCount.formatted(),
                    tint: BrandTokens.gold
                ),
                StatTile(id: "avg-accuracy", label: "Avg Accuracy", value: accuracyText(stats.averageAccuracy)),
                StatTile(
                    id: "best-rank", label: "Best Rank", value: rankText(stats.bestRank),
                    link: tileLink(PlayerStatLinks.overallBestRank(stats))
                ),
            ], scope: "overview", onSelect: open)
        }
        // `.contain` first, or the identifier replaces every tile's own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.player.overview")
        .quickLinkSection(id: "global", title: "Global Statistics", symbol: "chart.bar.fill")
    }

    // MARK: Per-instrument

    @ViewBuilder
    private func instrumentSection(_ payload: PlayerProfilePayload, instrument: Instrument) -> some View {
        let stats = payload.profile.instrumentStats(instrument)
        // Instrument header above its card, never inside it (web `InstrumentHeader` MD).
        // Web `buildInstrumentStatsItems` order: header, (empty state), Rank History
        // card, one card per stat, then the Percentiles table card.
        VStack(alignment: .leading, spacing: 12) {
            InstrumentSectionHeader(instrument, size: .medium)
            if stats.songsPlayed == 0 {
                FestivalGlassSection {
                    FestivalFootnote("No \(instrument.label) scores recorded yet.")
                        .accessibilityIdentifier("fst.player.instrument-empty.\(instrument.rawValue)")
                }
            } else {
                if !DualSourcePolicy.isActive(layout) {
                    PlayerRankHistoryCard(
                        session: session, accountId: accountId, instrument: instrument,
                        preloaded: historyPreloads[instrument]
                    )
                }
                InstrumentStatsCard(
                    session: session, accountId: accountId, instrument: instrument,
                    tiles: instrumentTiles(payload, stats: stats),
                    preloaded: rankPreloads[instrument],
                    linkFilter: tileLink, onSelect: open
                )
                if !DualSourcePolicy.isActive(layout) {
                    PlayerPercentileTableCard(
                        buckets: payload.profile.percentileBuckets(instrument), instrument: instrument,
                        linkFilter: tileLink, onSelect: open
                    )
                }
            }
        }
        // `.contain` first, or the identifier replaces every tile's own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.player.instrument.\(instrument.rawValue)")
        .quickLinkSection(QuickLinkSection(
            id: "instrument:\(instrument.rawValue)", title: instrument.label, icon: .instrument(instrument)
        ))
    }

    /// The web `buildInstrumentStatsItems` tiles before its rank cards, in its order:
    /// Songs Played and FCs (filter Songs), star counts (non-zero only; Songs stars
    /// filter + Stars sort), Avg Accuracy, Avg Stars, Best Rank (song).
    ///
    /// - Parameters:
    ///   - payload: Current validated profile read.
    ///   - stats: That instrument's aggregate.
    /// - Returns: Tiles; the card appends its global-rank tiles.
    private func instrumentTiles(_ payload: PlayerProfilePayload, stats: PlayerInstrumentStats) -> [StatTile] {
        let instrument = stats.instrument
        let stars = payload.profile.starBreakdown(instrument)
        var tiles = [
            StatTile(
                id: "songs-played", label: "Songs Played", value: stats.songsPlayed.formatted(),
                link: tileLink(PlayerStatLinks.instrumentSongsPlayed(instrument))
            ),
        ]
        if stats.fullComboCount > 0 {
            tiles.append(StatTile(
                id: "full-combos", label: "Full Combos",
                value: fullComboText(count: stats.fullComboCount, percent: stats.fullComboPercent),
                tint: stats.fullComboPercent >= 100 ? BrandTokens.gold : nil,
                link: tileLink(PlayerStatLinks.instrumentFullCombos(instrument))
            ))
        }
        tiles += stars.countCards.map { card in
            StatTile(
                id: "stars-\(card.stars)", label: card.label, value: card.count.formatted(),
                tint: card.stars == 6 ? BrandTokens.gold : nil,
                link: tileLink(PlayerStatLinks.instrumentStars(instrument, starKey: card.stars))
            )
        }
        tiles += [
            StatTile(id: "avg-accuracy", label: "Avg Accuracy", value: accuracyText(stats.averageAccuracy)),
            StatTile(id: "avg-stars", label: "Avg Stars", value: stars.averageText, goldStars: stars.isAllGold),
            StatTile(
                id: "best-rank", label: "Best Rank", value: rankText(stats.bestRank),
                link: tileLink(PlayerStatLinks.instrumentBestRank(stats))
            ),
        ]
        return tiles
    }

    // MARK: Regular-width grid

    private var instrumentGridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 20, alignment: .top), GridItem(.flexible(), spacing: 20, alignment: .top)]
    }

    /// One instrument's block: header, Rank History, stat cards and Percentiles (each
    /// its own card). Split around the Duo fold, the graphs live in the bottom region.
    ///
    /// - Parameters:
    ///   - payload: Current validated profile read.
    ///   - instrument: Settings-visible solo chart.
    @ViewBuilder
    private func instrumentTile(_ payload: PlayerProfilePayload, instrument: Instrument) -> some View {
        instrumentSection(payload, instrument: instrument)
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
                Image(systemName: "chevron.forward")
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

    /// Web FC value: the count alone at 0 or 100%, otherwise "count (pct%)".
    private func fullComboText(count: Int, percent: Double) -> String {
        count == 0 || percent >= 100 ? count.formatted() : "\(count.formatted()) (\(percentText(percent))%)"
    }

    /// "#rank", or an em dash with no ranked score.
    private func rankText(_ rank: Int?) -> String {
        rank.map { "#\($0.formatted())" } ?? "\u{2014}"
    }

    /// `PlayerScore.accuracy` already decodes into the same ten-thousandths-of-a-percent
    /// scale `ScoreFormatting.accuracy(_:)` expects (compact wire `acc` multiplied by
    /// 1,000; e.g. wire `979` becomes `979_000`, i.e. 97.9%) — no further rescale needed.
    private func accuracyText(_ playerProfileAccuracy: Double?) -> String {
        guard let playerProfileAccuracy else { return "—" }
        return "\(ScoreFormatting.accuracy(playerProfileAccuracy))%"
    }

    // MARK: Load

    /// Read the public profile without selecting or persisting it, then (in parallel)
    /// every played visible instrument's ranking and rank history, and only then show
    /// the page (web `PlayerPage` `dataReady`).
    private func load() async {
        phase = .loading
        do {
            let payload = try await session.viewPlayer(accountId: accountId)
            try Task.checkCancellation()
            guard payload.state != .syncing else {
                phase = .syncing
                return
            }
            let played = visibleInstruments.filter { payload.profile.instrumentStats($0).songsPlayed > 0 }
            let extras = await ProfileExtrasLoader.load(session: session, accountId: accountId, instruments: played)
            try Task.checkCancellation()
            rankPreloads = extras.ranks
            historyPreloads = extras.histories
            phase = .available(payload)
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

